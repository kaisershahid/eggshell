# This class is the root namespace for parsing and evaluating expressions.
# Each instance has its own parser and evaluator and provides convenience
# methods to quickly run an expresion.
module Eggshell; class ExpressionEvaluator
	ESCAPE_MAP = {
		'\\n'=> "\n",
		'\\r' => "\r",
		'\\t' => "\t",
		"\\(" => "(",
		"\\)" => ")",
		"\\{" => "{",
		"\\}" => "}",
		"\\[" => "[",
		"\\]" => "]",
		"\\'" => "'",
		'\\"' => '"'
	}.freeze
	
	OPERATOR_MAP = {
		'='.to_sym => 1000,
		'=='.to_sym => 999,
		'!='.to_sym => 999,
		'<'.to_sym => 990,
		'<='.to_sym => 990,
		'>'.to_sym => 990,
		'>='.to_sym => 990,
		'?'.to_sym => 900,
		':'.to_sym => 899,
		'<<'.to_sym => 200,
		'>>'.to_sym => 200,
		'~'.to_sym => 200,
		'&'.to_sym => 200,
		'|'.to_sym => 199,
		'*'.to_sym => 150,
		'/'.to_sym => 150,
		'%'.to_sym => 150,
		'^'.to_sym => 150,
		'+'.to_sym => 100,
		'-'.to_sym => 100,
		'&&'.to_sym => 99,
		'||'.to_sym => 99
	}.freeze
	
	def initialize(vars = nil, funcs = nil)
		@vars = vars || {}
		@funcs = funcs || {}
		@cache = {}
		@parser = Parser::DefaultParser.new
		#@evaluator = Evaluator.new(@vars, @funcs)
	end
	
	# Maps 1 or more virtual function names to a handler.
	# 
	# Virtual functions take the form of `funcname` or `ns:funcname`. When
	# registering functions, all function names will be mapped to the same
	# namespace that's passed in. If no names are given, the handler will
	# be set to handle all function calls in the namespace.
	# 
	# The handler should either handle 1-to-1 function calls (e.g. `ns:func` 
	# goes to `handler.func()`) or it should contain the following method
	# signature: `def exec_func(funcname, args = [])`. If there's a 1-to-1
	# match, arguments are expanded into individual arguments instead of
	# an array.
	# 
	# @todo expand mapping of functions so that we don't have to check each
	# time a func is referenced whether handler can handle it (only applies
	# to explicit names)
	def register_functions(handler, names = nil, ns = '')
		names = names.split(',') if names.is_a?(String) && names.strip != ''
		if names.is_a?(Array)
			names.each do |name|
				@funcs["#{ns}:#{name}"] = handler
			end
		else
			@funcs["#{ns}:"] = handler
		end
	end

	attr_reader :vars, :funcs, :parser

	def parse(statement, cache = true)
		parsed = @cache[statement]
		return parsed if cache && parsed

		parsed = @parser.parse(statement)
		@cache[statement] = parsed if cache
		return parsed
	end

	def evaluate(statement, do_parse = true, cache = true, vtable = nil, ftable = nil)
		vtable = @vars if !vtable.is_a?(Hash)
		ftable = @funcs if !ftable.is_a?(Hash)
		parsed = statement

		if !statement.is_a?(Array)
			return statement if !do_parse || !statement.is_a?(String)
			parsed = parse(statement, cache)
		end

		ret = nil
		parsed.each do |frag|
			ftype = frag[0]
			if ftype == :op
				op_val = frag[1][0].is_a?(Array) ? evaluate([frag[1][0]], false) : frag[1][0]
				z = 1
				while z < frag[1].length
					op = frag[1][z]
					rop = frag[1][z+1]
					rop = evaluate([rop]) if rop.is_a?(Array)
					op_val = self.class.op_eval(op_val, op, rop)
					z += 2
				end
				ret = op_val
			elsif ftype == :op_tern
				cond = frag[1].is_a?(Array) ? evaluate(frag[1]) : frag[1]
				if cond
					ret = frag[2].is_a?(Array) ? evaluate(frag[2], false) : frag[2]
				else
					ret = frag[3].is_a?(Array) ? evaluate(frag[3], false) : frag[3]
				end
			elsif ftype == :func
				fname = frag[1]
				ns, name = fname.split(':')
				if !name
					name = ns
					ns = ':'
					fname = ':' + name
				else
					ns += ':'
				end

				handler = ftable[fname]
				if !handler && ftable[ns]
					handler = ftable[ns]
				end
				
				_args = []
				frag[2].each do |ele|
					_args << (ele.is_a?(Array) && ele[0].is_a?(Symbol) ? evaluate([ele]) : ele)
				end
				
				# 1. check for exact func name
				# 2. check for :exec_func
				if handler.respond_to?(name.to_sym)
					ret = handler.send(name.to_sym, *frag[2])
				elsif handler.respond_to?(:exec_func)
					ret = handler.exec_func(name, frag[2])
				end
			elsif ftype == :var
				ret = var_get(frag, false, vtable)
			elsif ftype == :group
				ret = evaluate(frag[1], false, cache, vtable)
			elsif ftype == :array
				arr = []
				i = 1
				while i < frag.length
					arr << (frag[i].is_a?(Array) ? evaluate(frag[i]) : frag[i])
					i += 1
				end
				ret = arr
			elsif ftype == :hash
				map = {}
				i = 1
				while i < frag.length
					k = frag[i]
					v = frag[i+1]
					k = evaluate(k) if k.is_a?(Array) && k[0].is_a?(Symbol)
					v = evaluate(v) if v.is_a?(Array) && v[0].is_a?(Symbol)
					map[k] = v
					i += 2
				end
				ret = map
			elsif !ftype.is_a?(Symbol)
				# assumes a literal
				ret = ftype
			end
		end
		
		ret
	end
	
	# @todo have one set for strings, one set for numbers, and a general set for everything else
	# @todo what to do with unsupported ops?
	def self.op_eval(lop, op, rop)
		if (lop.is_a?(Numeric) && rop.is_a?(Numeric)) || lop.is_a?(rop.class)
			op = op.to_s
			case op
			when '==='
				return lop === rop
			when '=='
				return lop == rop
			when '!='
				return lop != rop
			when '+'
				return lop + rop
			when '-'
				return lop - rop
			when '/'
				return lop / rop
			when '*'
				return lop * rop
			when '<<'
				return lop << rop
			when '>>'
				return lop >> rop
			when '<'
				return lop < rop
			when '<='
				return lop <= rop
			when '>'
				return lop > rop
			when '>='
				return lop >= rop
			when '|'
				return lop | rop
			when '||'
				return lop || rop
			when '&'
				return lop & rop
			when '&&'
				return lop && rop
			when '%'
				return lop % rop
			when '^'
				return lop ^ rop
			when '='
				# @todo assign rop to lop
			end
		else
			
		end
	end
	
	def var_get(var, do_ptr = false, vtable = nil)
		vtable = @vars if !vtable
		if var.is_a?(String)
			if var.match(/^[a-zA-Z_][a-zA-Z0-9_\.]*$/)
				return vtable[var] if vtable.has_key?(var)
			end
			var = @parser.parse(var)
		end

		ptr_lst = nil
		ptr = vtable

		i = 0
		parts = var
		# @todo if do_ptr, set it as parts.length - 1? (and avoid having to save ptr_lst)
		while (i < parts.length)
			part = parts[i]
			ptr_lst = ptr
			if part == :var
				key = parts[i+1]
				if ptr.is_a?(Hash) && ptr[key]
					ptr = ptr[key]
					if ptr != nil
						i += 2
						next
					else
						break
					end
				else
					ptr = nil
					break
				end
			elsif part[0] == :index_access
				idx = part[1]
				if idx.is_a?(Array)
					idx = var_get(idx)
					if idx == nil
						ptr = nil
						break
					end
				end
				if (ptr.is_a?(Array) || ptr.is_a?(Hash)) && ptr[idx]
					ptr = ptr[idx]
				else
					ptr = nil
					break
				end
			elsif part[0] == :member_access
				mname = 'get_' + part[1]
				if ptr.respond_to?(mname.to_sym)
					ptr = ptr.send(mname.to_sym)
				else
					ptr = nil
					break
				end
			elsif part[0] == :func
				ptr = evaluate(part, false)
				break if ptr == nil
			end
			i += 1
		end
		
		return do_ptr ? ptr_lst : ptr
	end

	def var_set(var, val)
	end
	
	def test_func(*args)
		puts "test_func: #{args.inspect}"
	end
end; end

require_relative './expression-evaluator/lexer.rb'
require_relative './expression-evaluator/parser.rb'
require_relative './expression-evaluator/evaluator.rb'
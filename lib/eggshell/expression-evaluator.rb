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

	OP_ASSIGN = '='.to_sym
	OP_EQQ = :===
	OP_EQ = :==
	OP_NEQ = :!=
	OP_MATCH = :=~
	OP_NMATCH = '!=~'.to_sym
	OP_MULTIPLY = :*
	OP_DIVIDE = :/
	OP_ADD = :+
	OP_SUBTRACT = :-
	
	# Values give corresponding order of precedence
	OPERATOR_MAP = {
		OP_ASSIGN => 1000,
		OP_EQQ => 999,
		OP_EQ => 998,
		OP_NEQ => 998,
		OP_MATCH => 997,
		OP_NMATCH => 997,
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
		OP_MULTIPLY => 150,
		OP_DIVIDE => 150,
		'%'.to_sym => 150,
		'^'.to_sym => 150,
		OP_ADD => 100,
		OP_SUBTRACT => 100,
		'&&'.to_sym => 99,
		'||'.to_sym => 99
	}.freeze
	
	def initialize(vars = nil, funcs = nil)
		@vars = vars || {}
		@funcs = funcs || {}
		@cache = {}
		@parser = Parser::DefaultParser.new
		#@evaluator = Evaluator.new(@vars, @funcs)
		@func_whitelist = {}
		@func_wl_alias = {}
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
	
	# Registers 1+ getters and/or setters for a given class/module, avoiding
	# need to alias or proxy methods to use `get_` and `set_` names.
	def register_function_whitelist(clz, getters, setters = nil)
		if !clz.is_a?(String)
			clz = clz.name if clz.is_a?(Class)
			#clz = clz.name if clz.is_a?(Class)
		end
		@func_whitelist[clz] = {:get => {}, :set => {}}
		if getters.is_a?(Array)
			getters.each do |get|
				@func_whitelist[clz][:get][get] = true
			end
		end
		if setters.is_a?(Array)
			setters.each do |set|
				@func_whitelist[clz][:set][set] = true
			end
		end
	end
	
	# The function whitelist expects a given object's class to be a direct
	# mapping into the whitelist. Use this method to register all super classes
	# and interfaces of the given object that can be looked up if a mapping
	# fails.
	def register_function_alias(obj)
		clz = obj.is_a?(Class) ? obj : obj.class
		ptr = []
		clz.ancestors.each do |anc|
			next if anc == clz
			ptr << anc.name
		end
		@func_wl_alias[clz.name] = ptr
	end
	
	def resolve_function_alias(obj)
		clz = obj.is_a?(Class) ? obj.name : obj.class.name
		return @func_wl_alias[clz] || []
	end
	
	def has_function_alias(obj, func_name, type = :get)
		clz = obj.is_a?(Class) ? obj.name : obj.class.name
		if @func_whitelist[clz] && @func_whitelist[clz][type][func_name]
			return true
		end
		
		ret = false
		if @func_wl_alias[clz]
			@func_wl_alias[clz].each do |ali|
				ali = @func_whitelist[ali]
				if ali && ali[type][func_name]
					ret = true
					break
				end
			end
		end
		
		return ret
	end
	
	def get_function_aliases
		ret = []
		@func_whitelist.each do |clz, map|
			ret << clz
			ret << "\tgetters: #{map[:get].keys.join(', ')}"
			ret << "\tsetters: #{map[:set].keys.join(', ')}"
		end
		@func_wl_alias.each do |clz, arr|
			ret << clz
			arr.each do |ali|
				star = @func_whitelist[ali] ? ' *' : ''
				ret << "\t=> #{ali}#{star}"
			end
		end
		ret
	end

	attr_reader :vars, :funcs, :parser

	def parse(statement, cache = true)
		if cache
			parsed = @cache[statement]
			return parsed if parsed
		end

		@cache[statement] = @parser.parse(statement)
		return @cache[statement].clone
	end

	def evaluate(statement, do_parse = true, cache = true, vtable = nil, ftable = nil)
		vtable = @vars if !vtable.is_a?(Hash)
		ftable = @funcs if !ftable.is_a?(Hash)
		parsed = statement
		#$stderr.write "!!! #{vtable.inspect} // #{@vars.inspect} !!!\n"
		#$stderr.write "parsed = #{parsed.inspect}||vtable=#{vtable.inspect}\n"
		if !statement.is_a?(Array)
			return statement if !do_parse || !statement.is_a?(String)
			parsed = parse(statement, cache)
		elsif parsed[0].is_a?(Symbol)
			parsed = [parsed]
			#$stderr.write "^^ fixed up\n"
		end

		ret = nil
		parsed.each do |frag|
			ftype = frag[0]
			puts "ftype=#{ftype}"
			if ftype == :op
				# [:op, [operand, operator, operand(, operator, operand, ...)]]
				# z contains the start index of the operator-operand list. if the first operator is '=',
				# reserve first operand as var reference and evaluate everything after '=' before storing
				# into var ref
				z = 0
				oplist = frag[1]
				if oplist[1] == OP_ASSIGN
					if !oplist[0].is_a?(Array) || oplist[0][0] != :var
						raise Exception.new("Illegal assignment to non-variable: #{frag[1][0].inspect}")
					end
					z = 2
				end

				op_val = oplist[z]
				if op_val.is_a?(Array)
					op_val = op_val[0] == :var ? var_access(op_val) : evaluate([oplist[z]], false)
				end

				z += 1
				while z < oplist.length
					op = oplist[z]
					rop = oplist[z+1]
					if rop.is_a?(Array)
						rop = rop[0] == :var ? var_access(rop) : evaluate([rop])
					end
					ov = op_val
					op_val = self.class.op_eval(op_val, op.to_sym, rop)
					puts "#{ov} #{op} #{rop} = #{op_val}"
					z += 2
				end
				ret = op_val
				
				# var assignment; return true for successful set or false otherwise
				if oplist[1] == OP_ASSIGN
					ret = var_access(oplist[0], nil, ret)
				end
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
				#$stderr.write "<<< VAR\n"
				ret = var_access(frag, vtable)[0]
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
	
	def self.op_eval(lop, op, rop)
		#$stderr.write "op_eval:\n\t#{lop.inspect} #{op.inspect} #{rop.inspect}\n"
		if (lop.is_a?(Numeric) && rop.is_a?(Numeric))
			if op == OP_MATCH || op == OP_NMATCH
				raise Exception.new("'#{op}' can only be used with strings -- #{lop} #{op} #{rop}")
			end
			return lop.send(op, rop)
		elsif op == OP_EQQ
			return lop === rop
		elsif rop == :empty && (op == OP_EQ || op == OP_NEQ)
			# essentially (lop == false || lop == nil || lop == '') [==|!=] true
			# @todo other conditions to check empty?
			return (lop == false || lop == nil || lop == '').send(op, true)
		elsif lop.is_a?(String)
			e = nil
			if op == OP_MULTIPLY
				if rop.is_a?(Numeric)
					return lop * rop
				else
					e = "multiply string with numeric, #{rop.class} given"
				end
			elsif op == OP_MATCH || op == OP_NMATCH
				if rop.is_a?(String)
					m = lop.match(rop)
					if op == OP_NMATCH
						m = m == nil ? true : false
					end
					return m
				else
					e = "'#{op}' expects right operand to be string, #{rop.class} given"
				end
			elsif op == OP_ADD
				return lop + rop
			end
					
			raise Exception.new(e) if e
		elsif lop.is_a?(Array)
			if op == OP_MULTIPLY && rop.is_a?(Numeric)
				return lop * rop
			elsif (op == OP_ADD || op == OP_SUBTRACT) && rop.is_a?(Array)
				return lop.send(op, rop)
			end
			raise Exception.new("unsupported operation: #{lop.class} #{op} #{rop.class}")
		else
			
		end
	end
	
	# Gets or sets a variable reference. If reference is a string, an exact match is looked for
	# in vars table, otherwise an array (complex reference) is expected. If a value is given
	# in the `set_var` parameter, an attempt is made to assign the value (provided there's
	# a suitable method to handle setting).
	#
	# For a complex variable reference, iteratively chains a parent var with a child variable
	# identifier. The return value is an array that returns the resolved value, its parent var,
	# and the final identifier. In the case of setting, the resolved value is {{true}} if a setter
	# was found and {{false}} otherwise.
	#
	# @param String|Array var If a string, an exact match is attempted in vars table, 
	# otherwise an array with a parsed variable expression is expected.
	# @param Hash vtable Optional vars table. If `nil`, uses `@vars`.
	# @param Object set_var If not equivalent to `:nope`, assumes some sort of assignment.
	# A symbol is used as a check since symbols are not supported in expressions.
	# @return Array A 3-element array in the following format: `[value, parent_var, child_var_ident]
	def var_access(var, vtable = nil, set_var = :nope)
		vtable = @vars if !vtable
		if var.is_a?(String)
			return :empty if var == 'empty'
			if var.match(/^[a-zA-Z_][a-zA-Z0-9_\.]*$/)
				if vtable.has_key?(var)
					if set_var == :nope
						return [vtable[var], nil, nil]
					else
						vtable[var] = set_var
						return [true, nil, nil]
					end
				end
			end
			var = @parser.parse(var)
		end
		
		return :empty if var[1] == 'empty'

		ptr_lst = nil
		ptr = vtable
		i = 0
		parts = var
		set_point = set_var == :nope ? parts.length + 1 : parts.length - 1
		while (i < parts.length && ptr != nil)
			part = parts[i]
			ptr_lst = ptr
			if part == :var
				key = parts[i+1]
				if ptr.is_a?(Hash)
					if i == set_point
						ptr[key] = set_var
						ptr = true
					elsif ptr[key]
						ptr = ptr[key]
						if ptr != nil
							i += 2
							next
						end
					else
						ptr = nil
					end
				else
					ptr = nil
				end
			elsif part[0] == :index_access
				idx = part[1]
				if idx.is_a?(Array)
					idx = var_access(idx)[0]
					if idx == nil
						ptr = nil
						break
					end
				end
				if (ptr.is_a?(Array) || ptr.is_a?(Hash))
					if i == set_point
						ptr[idx] = set_var
						ptr = true
					else
						ptr = ptr[idx]
					end
				else
					ptr = nil
				end
			elsif part[0] == :member_access
				if ptr.is_a?(Hash)
					if i == set_point
						ptr[part[1]] = set_var
						ptr = true
					else
						ptr = ptr[part[1]]
					end
				else
					prefix = 'get_'
					type = :get
					if i == set_point
						prefix = 'set_'
						type = :set
					end

					mname = (prefix + part[1]).to_sym
					tgt = nil

					if ptr.respond_to?(mname)
						tgt = mname
					elsif has_function_alias(ptr, part[1], type)
						tgt = part[1].to_sym
					end
					if tgt
						if type == :set
							ptr.send(tgt, set_var)
							ptr = true
						else
							ptr = ptr.send(tgt)
						end
					else
						ptr = nil
					end
				end
			elsif part[0] == :func
				# @todo throw exception if this is set_point?
				# @todo what happens when we have `var[something](fn_args)`
				ptr = evaluate(part, false)
			end
			i += 1
		end
		return [ptr, ptr_lst, parts[-1]]
		#return do_ptr ? ptr_lst : ptr
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
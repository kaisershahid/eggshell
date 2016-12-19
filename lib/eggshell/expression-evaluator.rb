# Parses and evaluates statements (expressions). Can be used statically or
# as an instance.
module Eggshell;end
class Eggshell::ExpressionEvaluator
	REGEX_EXPR_PLACEHOLDERS = /(\\|\$\[|\$\{|\]|\}|\+|\-|>|<|=|\s+|\(|\)|\*|\/`)/
	REGEX_EXPR_STATEMENT = /(\(|\)|,|\[|\]|\+|-|\*|\/|%|<=|>=|==|<|>|"|'|\s+|\\|\{|\}|:|\?)/
	REGEX_OPERATORS = /\+|-|\*|\/|%|<=|>=|<|>|==|!=|&&|\|\||&|\|/

	LOG_OP = 2
	LOG_LEVEL = 0

	OP_PRECEDENCE = {
		'++' => 150, '--' => 150,
		'*' => 60, '/' => 60, '%' => 60,
		'<<' => 55, '>>' => 55,
		'+' => 51, '-' => 50,
		'<' => 49, '>' => 49, '<=' => 49, '=>' => 49,
		'==' => 48, '!=' => 48,
		'&' => 39,
		'^' => 38,
		'|' => 37,
		'&&' => 36,
		'||' => 35
	}.freeze

	OP_RTL = {
	}.freeze

	class ExprArray < Array
		attr_accessor :dynamic
		attr_reader :dyn_keys

		# Adds a term to the array. If it's a dynamic statement, its position is
		# marked and this array is marked as dynamic for evaluation later.
		def <<(term)
			@dyn_keys = [] if !@dyn_keys

			# cascade dynamic status
			if term.is_a?(ExprArray) || term.is_a?(ExprHash)
				if term.dynamic
					@dynamic = true
					@dyn_keys << self.length
				end					
			elsif term.is_a?(Array)
				if term[0] == :op
					
				end
				term, dyn = Eggshell::ExpressionEvaluator::struct_compact(term)
				if dyn
					@dynamic = true
					@dyn_keys << self.length
				end
			end

			self.push(term)
		end
	end

	class ExprHash < Hash
		attr_accessor :dynamic
		attr_reader :dyn_keys

		def add_term(key, term)
			@dyn_keys = [] if !@dyn_keys

			if term.is_a?(ExprArray) || term.is_a?(ExprHash)
				if term.dynamic
					@dynamic = true
					@dyn_keys << key
				end					
			elsif term.is_a?(Array)
				term, dyn = Eggshell::ExpressionEvaluator::struct_compact(term)
				if dyn
					@dynamic = true
					@dyn_keys << key
				end
			end

			self[key] = term
		end
	end
	
	def initialize(vars = nil, funcs = nil)
		@vars = vars || {}
		@funcs = funcs || {}
		@cache = {}
	end
	
	# Registers a function for embedded expressions. Functions are grouped into namespaces,
	# and a handler can be assigned to handle all function calls within that namespace, or
	# a specific set of functions within the namespace. The root namespace is a blank string.
	#
	# @param String func_key In the form `ns` or `ns:func_name`. For functions in the 
	# root namespace, do `:func_name`.
	# @param Object handler
	# @param Array func_names If `func_key` only refers to a namespace but the handler
	# needs to only handle a subset of functions, supply the list of function names here.
	def register_functions(func_key, handler, func_names = nil)
		if !func_key.index(':') && func_names.is_a?(Array)
			func_names.each do |fname|
				@funcs[func_key+func_name] = handler
			end
		else
			@funcs[func_key] = handler
		end
	end

	attr_reader :vars, :funcs
	
	def parse(statement, cache = true)
		parsed = @cache[statement]
		return parsed if cache && parsed
		
		parsed = self.class.struct(statement)
		@cache[statement] = parsed if cache
		return parsed
	end

	def evaluate(statement, cache = true)
		parsed = parse(statement, cache)
		return self.class.expr_eval(parsed, @vars, @funcs)
	end

	# Normalizes a term.
	# @param Object term If `String`, attempts to infer type (either `Fixnum`, `Float`, or `[:var, varname]`)
	# @param Boolean preserve_str If true and input is string but not number, return string literal.
	def self.term_val(term, preserve_str = false)
		if term.is_a?(String)
			if preserve_str
				return term
			elsif term.match(/^-?\d+$/)
				return term.to_i
			elsif term.match(/^-?\d*\.\d+$/)
				return term.to_f
			elsif term == 'null' || term == 'nil'
				return nil
			elsif term == 'true'
				return true
			elsif term == 'false'
				return false
			end

			if term[0] == '-'
				return [:op, '-', 0, [:var, term[1..-1]], :group]
			else
				return [:var, term]
			end
		end
		return term
	end

	# Inserts a term into the right-most operand.
	# 
	# Operator structure: `[:op, 'operator', 'left-term', 'right-term']
	def self.op_insert(frag, term)
		while frag[3].is_a?(Array)
			frag = frag[3]
		end
		frag[3] = term
	end

	# Restructures operands if new operator has higher predence than previous operator.
	# @param String nop New operator.
	# @param Array frag Operator fragment.
	# @param Array stack Fragment stack.
	def self.op_precedence(nop, frag, stack)
		topfrag = frag
		lptr = topfrag
		errs "op_precedence: frag=#{frag.inspect}", 1

		# retrieve the right-most operand
		# lptr = [opB, [opA, left, right], [opC, left, right]]
		# frag = [opC, left, right]
		# @todo look out for :nested in [4]?
		while frag[3].is_a?(Array) && frag[3][0] == :op && frag[3][-1] != :group
			lptr = frag
			frag = frag[3]
		end

		if frag[0] == :op
			oop = frag[1]
			p0 = OP_PRECEDENCE[oop]
			p1 = OP_PRECEDENCE[nop]
			errs "op_precedence:   #{oop} (#{p0}) vs #{nop} (#{p1})", 0

			if p0 > p1
				# preserve previous fragment and make as left term of new op
				# [opA, left, right] ==> [opB, [opA, left, right], nil]
				nfrag = [:op, nop, topfrag.clone, nil]
				lptr[1] = nop
				lptr[2] = nfrag[2]
				lptr[3] = nil
			else
				frag[3] = [:op, nop, frag[3], nil]
			end
			stack << topfrag
		else
			stack << [:op, nop, frag, nil]
		end
	end

	def self.struct(str)
		errs "struct parse: #{str}", 9
		toks = str.split(REGEX_EXPR_STATEMENT)
		char_pos = 0
		state = [:nil]
		last_state = nil
		d = 0

		# each element on the stack points to a nested level (so root is 0, first parenthesis is 1, second is 2, etc.)
		# ptr points to the deepest level
		stack = [ [] ]
		ptr = stack[0]
		term = nil
		term_state = nil

		quote_delim = nil

		# last_key tracks the last key being built up in a map expression. this allows maps to contain maps
		map_key = nil
		last_key = []

		i = 0
		toks.delete('')

		# push a new operator or a term onto the stack
		_op_push = lambda {|operator|
			errs "_op_push: #{operator} (term=#{term}) (ptr[-1]=#{ptr[-1].inspect})", 1
			if term
				# check what the last item is. 
				frag = ptr.pop
				term = term_val(term, term_state == :quote)
				if frag.is_a?(Array) && frag[0] == :op
					op_insert(frag, term)
					if operator
						op_precedence(operator, frag, ptr)
					else
						ptr << frag
					end
				else
					ptr << frag if frag
					ptr << [:op, operator, term, nil]
				end

				errs ">> state=#{state.inspect}, stack=#{stack.inspect}", 0
				errs ">> frag=#{frag.inspect}", 0
				term = nil
				term_state = nil
			elsif operator
				# no term, so pushing operator. either generate new operator fragment or put in precedence order
				frag = ptr.pop
				if frag.is_a?(Array)
					if frag[0] == :op
						# preserve parenthesized group
						if frag[4] == :group
							ptr << [:op, operator, frag, nil]
						else
							op_precedence(operator, frag, ptr)
						end
					else
						ptr << [:op, operator, frag, nil]
					end
				elsif frag
					ptr << [:op, operator, frag, nil]
				else
					# @todo throw exception
				end
			end
		}

		# closes out a state
		_transition = lambda {|st|
			errs "_transition: :#{st} (term=#{term.class}, ts=#{term_state})", 1
			errs "state=#{state.inspect}"
			ret = nil
			if st == :op
				ret = st
				if term
					_op_push.call(nil)
					state.pop
					term = nil
					term_state = nil
					errs "_transition: ptr=#{ptr.inspect}", 1
				else
					# @todo throw exception
				end
				# @todo throw exception -- no closing ')'
			elsif st == :tern
				if term
					ptr << term_val(term, term_state == :quote)
					term = nil
					term_state = nil
				end

				if ptr[-4] == :tern
					right = ptr.pop
					left = ptr.pop
					cond = ptr.pop
					ptr.pop
					ptr << [:op_tern, cond, left, right]
				else
					# @todo throw exception
				end
			elsif term
				ret = :term
				ptr << term_val(term, term_state == :quote)
				errs "_transition: term <-- #{ptr.inspect}", 0
				term = nil
				term_state = nil
			elsif st == :fnop || st == :nest
			else
				# @todo throw exception?
			end
			
			return ret
		}

		errs "toks = #{toks.inspect}", 5
		while (i < toks.length)
			tok = toks[i]
			i += 1
			char_pos += tok.length
			errs "tok: #{tok} (state=#{state[-1]}, term=#{term})", 6
			if tok == '\\'
				i += 1 if toks[i] == ''
				char_pos += toks[i].length
				term += toks[i]
				i += 1
			elsif term_state == :quote
				if tok != quote_delim
					term += tok
				else
					quote_delim = nil
					_transition.call(state[-1])
					term = nil
					term_state = nil
				end
			elsif (tok == "'" || tok == '"')
				quote_delim = tok
				term = ''
				term_state = :quote
			elsif tok == ','
				errs "comma: ptr=#{ptr.inspect}", 5
				_transition.call(state[-1])
				term = nil
				term_state = nil
			elsif tok == '{'
				if state[-1] == :nil && stack[0][-1][0] == :fn
					delim = '{'
					while toks[i]
						delim += toks[i]
						i += 1
					end
					stack[0] << [:brace_op, delim]
					break
			  	end

				stack << []
				state << :hash
				ptr = stack[-1]
			elsif tok == '}'
				errs "}", 5
				_transition.call(state[-1])

				rawvals = stack.pop
				errs "rawvals=#{rawvals.inspect}", 4
				map = ExprHash.new
				imap = 0
				while (imap < rawvals.length)
					# @todo make sure key is scalar
					# @todo make sure length is even (indicates unbalanced map def otherwise)
					mkey = rawvals[imap]
					mkey = mkey[1] if mkey.is_a?(Array)
					map[mkey] = rawvals[imap+1]
					imap += 2
				end

				state.pop
				ptr = stack[-1]
				ptr << map
			elsif tok == '?'
				# mark the position
				if term
					ptr << :tern
					ptr << term_val(term, term_state == :quote)
					term = nil
					term_state = nil
				else
					last = ptr.pop
					ptr << :tern
					ptr << last
				end

				state << :tern
			elsif tok == ':'
				errs ": #{state[-1]} | ptr=#{ptr.inspect}", 5
				if state[-1] == :hash || state[-1] == :tern
					# case for this: when a key is quoted, the term is committed to the pointer already, so at ':' term is nil
					if term != nil
						ptr << term_val(term, term_state == :quote)
						term = nil
						term_state = nil
					end
					# @todo validate ternary stack length?
				else
					# @todo throw exception
				end
				errs "ptr=#{ptr.inspect}", 4
			elsif tok == '['
				stack << ExprArray.new
				state << :arr
				ptr = stack[-1]
			elsif tok == ']'
				last_state = _transition.call(state[-1])
				state.pop
				vals = stack.pop
				ptr = stack[-1]
				ptr << vals
			elsif tok == '('
				errs "(", 4
				if term
					# @todo throw exception if term is a quote?
					# @todo throw exception if term is not a valid word?
					frag = [:fn, term, nil]
					stack << frag
					stack << []
					state << :fnop
					ptr = stack[-1]
					term = nil
					term_state = nil
				else
					stack << []
					state << :nest
					ptr = stack[-1]
				end
			elsif tok == ')'
				last_state = _transition.call(state[-1])
				#while state[-1] != :fnop && state[-1] != :nest
				#	last_state = _transition.call(state[-1])
				#	break if state[-1] == :fnop || state[-1] == :nest
				#end
				nest_statement = stack.pop
				ptr = stack[-1]
				_state = state.pop
				errs ") nest_statement=#{nest_statement[0].inspect}", 5
				if _state == :fnop
					frag = stack.pop
					frag[2] = nest_statement
					ptr = stack[-1]
					ptr << frag
				elsif _state == :nest
					if nest_statement.length > 1
						# @todo throw exception, parenthetical expression should be reduced to single term
					end
					nest_statement = nest_statement.pop
					if !nest_statement.is_a?(Array)
						errs "#{str}", 0
						errs "!! nest: #{nest_statement}\n#{stack.inspect}", 0
					end
					nest_statement << :group
					inject_into(ptr, nest_statement)
				elsif _state == :op
					ptr << nest_statement
				else
					# @throw exception?
				end
			elsif tok.match(REGEX_OPERATORS)
				# assumes negative
				if tok == '-' && !term
					t = ptr.pop
					if t == nil
						term = '-'
						next
					else
						ptr << t
					end
				end
				# @todo more appropriate way to push stack? otherwise fn(1 + 2 + 3) gets 1 too many :op
				state << :op if state[-1] != :op
				_op_push.call(tok)
			elsif tok != ''
				# white space; close out state
				if tok.strip == ''
					_transition.call(state[-1]) if term
					next
				end

				if !term
					term = tok
				else
					term += tok
				end
				
				# look-ahead to build variable reference
				ntok = toks[i]
				while ntok
					if ntok != ',' && ntok != ':' && ntok != '(' && ntok != ')' && ntok != '}' && !ntok.match(REGEX_OPERATORS)
						if ntok != ' ' && ntok != "\t"
							term += ntok
						end
						i += 1
						ntok = toks[i]
					else
						break
					end
				end
			end
		end

		# @todo validate completeness of state (e.g. no omitted parenthesis)
		if state[1] || term
			_transition.call(state[-1])
		end

		errs "*** end state: #{state.inspect} ***", 2
		errs "*** end stack: #{stack.inspect} ***", 2
		return stack[0]
	end
	
	def self.inject_into(ptr, frag)
		if !ptr[-1]
			ptr << frag
		else
			if ptr[-1].is_a?(Array)
				if ptr[-1][0] == :op
					op_insert(ptr[-1], frag)
				end
				# @todo is there an else?
			end
			# @todo is there an else?
		end
	end

	# Takes the output of {@see struct} and evaluates static expressions to speed up
	# {@see expr_eval}.
	# @param Object struct The structure to compact.
	# @return Array `[struct, dynamic]`
	def self.struct_compact(struct)
		dyn = false

		if struct.is_a?(ExprArray) || struct.is_a?(ExprHash)
			# don't need to do anything -- add_term already compacts terms
			dyn = struct.dynamic
		elsif struct.is_a?(Array)
			# the only term that potentially is static is a logical or mathematical operation.
			# the operation will compact if all terms are static (e.g. can be evaluated now)
			if struct[0].is_a?(Symbol)
				if struct[0] == :op
					lterm = struct[2]
					if lterm.is_a?(Array)
						lstruct, ldyn = struct_compact(lterm)
						if !ldyn
							lterm = lstruct
						else
							lterm = nil
						end
					end

					rterm = struct[3]
					if rterm.is_a?(Array)
						rstruct, rdyn = struct_compact(rterm)
						if !rdyn
							rterm = rstruct
						else
							rterm = nil
						end
					end

					if lterm != nil && rterm != nil
						return [expr_eval_op(struct[1], lterm, rterm), false]
					else
						dyn = true
					end
				elsif struct[0] == :fn
					dyn = true
					struct[2] = struct_compact(struct[2])[0]
				else
					dyn = true
				end
			else
				i = 0
				while i < struct.length
					substruct = struct[i]
					substruct, sdyn = struct_compact(substruct)
					dyn = true if sdyn
					struct[i] = substruct
					i += 1
				end
			end
		else
			return [struct, false]
		end

		return [struct, dyn]
	end

	# @param Array expr An expression structure from @{see struct()}
	# @param Map vtable Map for variable references.
	# @param Map ftable Map for function calls.
	def self.expr_eval(expr, vtable, ftable)
		errs "expr_eval: #{expr.inspect}", 3
		expr = expr[0] if expr.is_a?(Array) && expr.length == 1

		ret = nil
		if expr.is_a?(ExprArray) || expr.is_a?(ExprHash)
			ret = expr.clone
			(expr.dyn_keys || []).each do |key|
				ret[key] = expr_eval(expr[key], vtable, ftable)
			end
		elsif expr.is_a?(Array)
			if expr[0] && !expr[0].is_a?(Symbol)
				ret = []
				i = 0
				expr.each do |subexpr|
					ret[i] = expr_eval(subexpr, vtable, ftable)
					i += 1
				end
			elsif expr[0]
				frag = expr
				if frag[0] == :op_tern
					cond = expr_eval(frag[1], vtable, ftable)
					if cond
						ret = expr_eval(frag[2], vtable, ftable)
					else
						ret = expr_eval(frag[3], vtable, ftable)
					end
				elsif frag[0] == :op
					op = frag[1]
					lterm = frag[2]
					rterm = frag[3]
					
					errs "lterm >> #{lterm.inspect}", 1
					errs "rterm >> #{rterm.inspect}", 1
					if lterm.is_a?(Array)
						if lterm[0] == :var
							lterm = retrieve_var(lterm[1], vtable, ftable)
						else
							lterm = expr_eval(lterm, vtable, ftable)
						end
					end
					if rterm.is_a?(Array)
						if rterm[0] == :var
							rterm = retrieve_var(rterm[1], vtable, ftable)
						else
							rterm = expr_eval(rterm, vtable, ftable)
						end
					end
					errs "lterm << #{lterm.inspect}", 0
					errs "rterm << #{rterm.inspect}", 0
					ret = expr_eval_op(op, lterm, rterm)
				elsif frag[0] == :fn
					# @todo see if fname itself has an entry, and call if it has method `func_call` (?)
					fkey = frag[1]
					args = frag[2]
					ns, fname = fkey.split(':')
					if !fname
						fname = ns
						ns = ''
					end
					fname = fname.to_sym

					handler = ftable[fkey]
					handler = ftable[ns] if !handler

					if handler && handler.respond_to?(fname)
						cp = []
						args.each do |arg|
							el = expr_eval(arg, vtable, ftable)
							cp << el
						end

						ret = ftable[ns].send(fname, *cp)
					else
						ret = nil
						# @todo log error or throw exception? maybe this should be a param option
					end
				elsif frag[0] == :var
					ret = retrieve_var(frag[1], vtable, ftable)
					if ret.is_a?(Array) && ret[0].is_a?(Symbol)
						ret = expr_eval(ret, vtable, ftable)
					end
				end
			end
		else
			return expr
		end
		return ret
	end

	def self.expr_eval_op(op, lterm, rterm)
		ret = nil
		#$stderr.write "** #{lterm.inspect} ( #{op} ) #{rterm.inspect}\n"
		case op
		when '=='
			ret = lterm == rterm
		when '!='
			ret = lterm != rterm
		when '<'
			ret = lterm < rterm
		when '>'
			ret = lterm > rterm
		when '<='
			ret = lterm <= rterm
		when '>='
			ret = lterm >= rterm
		when '+'
			ret = lterm + rterm
		when '-'
			ret = lterm - rterm
		when '*'
			ret = lterm * rterm
		when '/'
			ret = lterm / rterm
		when '%'
			ret = lterm % rterm
		when '&'
			ret = lterm & rterm
		when '|'
			ret = lterm | rterm
		when '&&'
			ret = lterm && rterm
		when '||'
			ret = lterm || rterm
		end
		# @todo support other bitwise
		return ret
	end

	# Attempts to a resolve a variable in the form `a.b.c.d` from an initial 
	# variable map. Using `.` as a delimiter, the longest match name is attempted
	# to be matched (e.g. `a.b.c.d`, then `a.b.c`, then `a.b`, then `a`), and any
	# remaining parts are considered getters than are chained together.
	#
	# For instance, if `a.b.c.d` partially resolves to `a.b`, then:
	# # check if `(a.b).c` is a valid key/index/method
	# # check if `(a.b.c).d` is a valid key/index/method
	#
	# If at any point a `nil` is encountered in the above scenario, a `nil` will 
	# be returned.
	# @param Boolean return_ptr If true, returns the object holding the value, not
	# the value itself.
	# @return Either the resolved value (or nil), or if `return_ptr` is true, a structure
	# in the form {{[n-1, [ley, type]]}} where `n-1` is the parent of the last key/get, 
	# {{key}} is the key/getter, and {{type}} is either {{:arr}} or {{:get}}/
	def self.retrieve_var(var, vtable, ftable, return_ptr = false)
		# @todo only do this when there's no [] and return_ptr is false
		errs "retrieve_var: #{var}", 5
		retval = vtable[var]

		if !retval
			# @todo more validation
			# @todo support key expressions?
			val = nil
			vparts = var.split(/(\.|\[|\])/)
			vparts.delete("")

			ptr = vtable
			last_ptr = nil
			last_key = nil

			i = 0
			key = ''
			type = :arr
			# need to quote first element so that loop doesn't assume this to be a var reference
			vparts[0] = "'#{vparts[0]}'"

			while i < vparts.length
				tok = vparts[i]
				errs "var:tok=#{tok}", 4
				i += 1
				check_key = false
				if tok == '.'
					type = :get
					check_key = true
				elsif tok == '['
					type = :arr
					check_key = true
				elsif tok == ']'
					check_key = true
				else
					key += tok
				end
				
				if check_key || !vparts[i]
					next if key == ''
					errs "var:check=#{key} (#{type})", 3
					# @todo if :arr but item doesn't respond to [], return nil?
					last_ptr = ptr
					if type == :arr
						if !ptr.respond_to?(:[]) || ptr.is_a?(Numeric)
							ptr = nil
							break
						end

						# lookup var reference if not quoted and not integer
						if key[0] == '"' || key[0] == "'"
							key = key[1...-1]
						elsif key.match(/[0-9]+/)
							key = key.to_i
						else
							key = retrieve_var(key, vtable, {}, false)
						end
						
						# make sure key is numeric for array
						if ptr.is_a?(Array) && !key.is_a?(Numeric)
							ptr = nil
							break
						end

						ptr = ptr[key]
						if ptr
							last_key = [key, :arr]
						else
							break
						end
					else
						# @todo sanity check? (no quotes, not numeric or starting with num)
						# @todo restrict to 'get_*'?
						meth1 = key.to_sym
						meth2 = ('get_' + key).to_sym
						if ptr.respond_to?(meth1)
							last_ptr = ptr
							ptr = ptr.send(meth1)
						elsif ptr.respond_to?(meth2)
							last_ptr = ptr
							ptr = ptr.send(meth2)
						else
							ptr = nil
							break
						end
					end

					key = ''
				end
			end

			retval = ptr
			if return_ptr
				if last_ptr != nil
					retval = [last_ptr, last_key]
				else
					retval = nil
				end
			end
		end

		return retval
	end
	
	# 
	def set_var(var, key, type, value)
		if type == :arr
			# @todo check key if Array
			if var.is_a?(Hash) || var.is_a?(Array)
				var[key] = value
			end
		else
			sym = "set_#{key}".to_sym
			if var.respond_to?(sym)
				var.send(sym, value)
			end
		end
	end

	def self.restructure(struct)
		if !struct.is_a?(Array)
			return struct
		elsif struct[0] == :op
			lterm = restructure(struct[2])
			rterm = restructure(struct[3])
			return "#{lterm} #{struct[1]} #{rterm}"
		elsif struct[0] == :var
			return struct[1]
		else
		end
	end
	
	def self.errs(str, lvl = 5)
		return if lvl < $errs_write
		$stderr.write "[#{lvl}]#{'  ' * ($errs_write_indent-lvl)}#{str}\n"
	end
end

$errs_write = 10
$errs_write_indent = 10
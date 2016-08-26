module TMD; end
# Parses and evaluates statements (expressions).
#
# pre.
# # simple expression
# 1 + 5
# 1 < (5 + 8) || 3 * 4 > 2
# 
# # arrays and maps
# [1, 2, 3]
# [1, [2, 3], 4]
# {'key': 'val', 'another': 'val2', 'num': 8.2}
# [1, {'key': 'val'}]
# {'arr': [1, 2, 3]}
# 
# # variables set via @var macro
# var.name + 5
#
# # function calls
# fn1(arg1, "arg2", 3) + fn2({}, [])
# /pre
class TMD::ExpressionEvaluator
	REGEX_EXPR_PLACEHOLDERS = /(\\|\$\[|\$\{|\]|\}|\+|\-|>|<|=|\s+|\(|\)|\*|\/`)/
	REGEX_EXPR_STATEMENT = /(\(|\)|,|\[|\]|\+|-|\*|\/|%|<=|>=|==|<|>|"|'|\s+|\\|\{|\}|:)/

	LOG_OP = 2
	LOG_LEVEL = 0

	OP_PRECEDENCE = {
		'*' => 60, '/' => 60, '%' => 60,
		'<<' => 55, '>>' => 55,
		'<' => 54, '>' => 54, '<=' => 54, '=>' => 54,
		'==' => 53, '!=' => 52,
		'&' => 50,
		'^' => 49,
		'|' => 48,
		'+' => 47, '-' => 47,
		'&&' => 45,
		'||' => 44
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
				term, dyn = TMD::ExpressionEvaluator::struct_compact(term)
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
				term, dyn = TMD::ExpressionEvaluator::struct_compact(term)
				if dyn
					@dynamic = true
					@dyn_keys << key
				end
			end

			self[key] = term
		end
	end

	# Normalizes a term.
	# @param Object term If `String`, attempts to infer type (either `Fixnum`, `Float`, or `[:var, varname]`)
	# @param Boolean preserve_str If true and input is string but not number, return string literal.
	def self.term_val(term, preserve_str = false)
		if term.is_a?(String)
			if preserve_str
				return term
			elsif term.match(/^\d+$/)
				return term.to_i
			elsif term.match(/^\d*\.\d+$/)
				return term.to_f
			elsif term == 'null' || term == 'nil'
				return nil
			end

			return [:var, term]
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
		frag[3] = term_val(term)
	end

	# Restructures operands if new operator has higher predence than previous operator.
	# @param String tok New operator.
	# @param Array frag Operator fragment.
	# @param Array stack Fragment stack.
	def self.op_precedence(tok, frag, stack)
		topfrag = frag
		lptr = nil
		# retrieve the right-most operand
		while frag[3].is_a?(Array) && frag[3][0] == :op
			lptr = frag
			frag = frag[3]
		end
		lptr = topfrag if !lptr

		if frag[0] == :op
			p1 = OP_PRECEDENCE[tok]
			p0 = OP_PRECEDENCE[frag[1]]
			if p1 > p0
				frag[3] = [:op, tok, frag[3], nil]
			else
				lptr[3] = [:op, tok, [:op, frag[1], frag[2], frag[3]], nil]
			end
			stack << topfrag
		else
			stack << [:op, tok, frag, nil]
		end
	end

	def self._trace(msg, lvl = 0)
	end

	# Converts a string expression into a tree structure that can be evaluated later.
	#
	# The root of the tree is an array. Each element can be one of the following terms:
	#
	# # String: `[:str, 'string']`
	# # Numbers and Booleans: `5, true, false, 3.14`
	# # Variable reference: `[:var, 'varname']`
	# # Function call: `[:fn, 'function-name', [term0, term1, ...]]`
	# # Operation: `[:op, left-term, right-term]`
	# # Array or Map: note that an explicit array's first element will never be a symbol,\
	# differentiating it from the other structures.
	#
	# Note that `args` is an array of any valid term.
	def self.struct(str)
		toks = str.split(REGEX_EXPR_STATEMENT)
		state = [:nil]
		last_state = nil
		d = 0

		# each element on the stack points to a nested level (so root is 0, first parenthesis is 1, second is 2, etc.)
		# ptr points to the deepest level
		stack = [[]]
		ptr = stack[0]
		term = nil

		quote_delim = nil

		# last_key tracks the last key being built up in a map expression. this allows maps to contain maps
		map_key = nil
		last_key = []

		i = 0
		while (i < toks.length)
			tok = toks[i]
			i += 1
			next if tok == ''

			# assumes term has been initialized through open quote
			# @todo any other contexts that \ is useful?
			if tok == '\\'
				i += 1 if toks[i] == ''
				term += toks[i]
				i += 1
			elsif state[d] == :quote
				if tok != quote_delim
					term += tok
				else
					quote_delim = nil
					state.pop
					d -= 1
					if state[d] != :map
						ptr << term
						term = nil
					end
					last_state = :quote
				end
			elsif (tok == "'" || tok == '"') && last_state != :term
				state << :quote
				d += 1
				quote_delim = tok
				term = ''
			elsif tok == '{'
				# special case: end delimiter
				if state[d] == :nil && last_state == :fnop
					delim = '{'
					while toks[i]
						delim += toks[i]
						i += 1
					end
					ptr << [:brace_op, delim]
					break
				end
				state << :map
				d += 1
				map = ExprHash.new
				stack << map
				ptr = map
			elsif tok == '['
				if last_state != :term
					state << :arr
					d += 1
					arr = ExprArray.new
					stack << arr
					ptr = arr
				else
					term += '['
				end
			elsif state[d] == :map && tok == ':'
				if map_key # preserve function
					term += ':'
				else
					map_key = term
					term = nil
				end
				last_state = :map_key
			elsif state[d] == :map && tok == '}'
				# @todo validate & convert term?
				ptr.add_term(map_key, term_val(term, last_state == :quote))
				map_key = nil
				term = nil

				state.pop
				d -= 1
				map = stack.pop
				ptr = stack[-1]
				ptr << map
			elsif last_state == :term && tok == ']'
				term += ']'
			elsif state[d] == :arr && tok == ']'
				if term
					term = term_val(term, last_state == :quote)
					ptr << term
					term = nil
				end

				last_state = state.pop
				d -= 1
				arr = stack.pop
				ptr = stack[-1]
				if state[d] != :map
					ptr << arr
				else
					term = arr
				end
			elsif tok.match(/\+|-|\*|\/|%|<=|>=|<|>|==|!=|&&|\|\||&|\|/)
				state << :op
				d += 1
				if term
					if ptr.length == 0
						ptr << [:op, tok, term_val(term), nil]
						term = nil
					else
						# @TODO this doesn't make sense. if there's a dangling term then there's a syntax error
						# ... x + y z - a ==> 'z' would be the term before '-' for something like this to happen
						last = ptr.pop
						ptr << [:op, tok, last, term_val(term)]
					end
				else
					if ptr.length > 0
						frag = ptr.pop
						# when you have x + y / ..., make it x + (y / ...)
						op_precedence(tok, term_val(frag), ptr)
					end
				end
			elsif tok == '('
				if term
					term = [:fn, term, []]
					if state[d] != :map
						ptr << term
					else
						ptr.add_term(map_key, term)
						last_key << map_key
						map_key = nil
					end
					term = nil

					state << :fnop
					d += 1
					arr = []
					stack << arr
					ptr = arr
				else
					state << :nest
					d += 1
					arr = []
					stack << arr
					ptr = arr
				end
			elsif tok == ')'
				lstate = last_state = state.pop
				lstack = stack.pop
				ptr = stack[-1]
				d = state.length - 1

				if lstate == :nest
					if state[d] == :fnop
						lstack.each do |item|
							ptr << item
						end
					elsif state[d] == :map
						term = lstack
					else
						frag = ptr[-1]
						if frag
							op_insert(frag, lstack)
						else
							lstack.each do |item|
								ptr << item
							end
						end
					end
				elsif lstate == :fnop
					if term
						lstack << term_val(term)
						term = nil
					end

					if state[d] == :map
						map_key = last_key.pop
						term = ptr[map_key]
						term[2] = lstack
					else
						ptr[-1][2] = lstack
					end
				end
			elsif tok == ','
				# @todo if term is nil and ptr.length == 0, assume an error
				if term
					if state[d] == :map
						# @todo map validation
						ptr.add_term(term_val(map_key, true), term_val(term, last_state == :quote))
						map_key = nil
						term = nil
					else
						term = term_val(term, last_state == :quote)
						ptr << term
						term = nil
					end
					last_state = :comma
				end
			#elsif tok == '#'
			elsif tok.strip != ''
				term = term ? term + tok : tok

				if state[d] == :op
					if ptr[-1] == nil
						# @throw exception
					elsif ptr[-1][0] == :op
						frag = ptr[-1]
						op_insert(frag, term_val(term, last_state == :quote))
						term = nil
					else
						# ???
					end
					last_state = state.pop
					d -= 1
				elsif state[d] == :map
					# ?
				elsif state[d-1] == :fnop
					ptr << term_val(term, last_state == :quote)
					term = nil
				else
					last_state = :term
				end
			end
		end

		# @todo cleanup
		if state[d] == :op && term
			frag = ptr[-1]
			if frag[0] == :op
				op_insert(frag, term)
			end
		elsif state[d] == :quote
			ptr << [:str, term]
		else
			if term
				ptr << [:var, term]
			end
		end

		return stack[0]
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
		end

		return [struct, dyn]
	end

	# @param Array expr An expression structure from @{see struct()}
	# @param Map vtable Map for variable references.
	# @param Map ftable Map for function calls.
	def self.expr_eval(expr, vtable, ftable)
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
				if frag[0] == :op
					op = frag[1]
					lterm = frag[2]
					rterm = frag[3]

					if lterm.is_a?(Array)
						lterm = expr_eval(lterm, vtable, ftable)
					end
					if rterm.is_a?(Array)
						rterm = expr_eval(rterm, vtable, ftable)
					end

					ret = expr_eval_op(op, lterm, rterm)
				elsif frag[0] == :fn
					# @todo see if fname itself has an entry, and call if it has method `func_call` (?)
					fname = frag[1]
					args = frag[2]
					ns, fname = fname.split(':')
					if !fname
						fname = ns
						ns = ''
					end
					fname = fname.to_sym

					if ftable[ns] && ftable[ns].respond_to?(fname)
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
					ret = retrieve_var(frag[1], vtable)
				end
			end
		end
		return ret
	end

	def self.expr_eval_op(op, lterm, rterm)
		ret = nil
		case op
		when '=='
			ret = lterm == rterm
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
	# @todo make last_ptr nil if full resolution fails
	def self.retrieve_var(var, vtable, return_ptr = false)
		return vtable[var] if vtable[var]
		# @todo more validation
		# @todo support key expressions?
		val = nil
		vparts = var.split(/(\.|\[|\]\[|\])/)
		ptr = vtable
		last_ptr = nil

		i = 0
		key = nil
		type = nil
		while i < vparts.length
			tok = vparts[i]
			i += 1
			if tok == '.'
				type = :get
			elsif tok == '['
				type = :arr
			elsif tok == '][' || tok == ']'
				type = :get if tok == ']'
			else
				key = tok
				if ptr == vtable
					ptr = vtable[key]
					break if ptr == nil
					next
				end

				last_ptr = ptr
				if type == :get
					meth1 = key.to_sym
					meth2 = ('get_' + key).to_sym
					if ptr.respond_to?(meth1)
						ptr = ptr.send(meth1)
					elsif ptr.respond_to?(meth2)
						ptr = ptr.send(meth2)
					end
				else
					if key[0] == '"' || key == "'"
						key = key[1...-1]
					else
						key = retrieve_var(key, vtable)
					end

					if key
						if ptr.is_a?(Hash)
							ptr = ptr[key]
						elsif ptr.is_a?(Array)
							if key.is_a?(String) && key.match(/-?\d+/)
								key = key.to_i
							end
							ptr = ptr[key]
						end
					end
				end
			end
		end

		if return_ptr
			return last_ptr
		else
			return ptr
		end
	end

	def self.fn(arg1, arg2, arg3 = nil)
		puts "fn: 1:#{arg1}, \n\t2:#{arg2}\n\t3:#{arg3}"
	end

	def self.test_retrieve_var
		vtable = {}
		ftable = {}
		vtable['map'] = {'k1'=>'val_k1', 'submap' => {'banh'=>'mi'}}
		vtable['str_obj'] = 'this is a strong'
		vtable['map.submap'] = 14
		#puts "map.k1 => #{retrieve_var('map.k1', vtable)}"
		puts "map['submap']['banh'] => #{retrieve_var('map["submap"]["banh"]', vtable)}"
		puts "map[submap]['banh'] => #{retrieve_var('map[submap]["banh"]', vtable)}"
		#puts "str_obj => #{retrieve_var('str_obj', vtable)}"
		#puts "str_obj.length => #{retrieve_var('str_obj.length', vtable)}"
	end

	def self.test_struct
		vtable = {'val' => 'VALUE'}
		ftable = {'' => TMD::ExpressionEvaluator}

		expr1 = "x.y[0]['1']"
		expr2 = "fn(#{expr1}, a[1])"
		expr3 = "5 + 8 / 4 + 6"
		expr4 = "{key : 'val', val: 55.0, another: val}"
		expr5 = "{key : val, val: 55.0}"
		expr6 = "fn(#{expr4}, [1 < 5, 0, 1], {'k': val})"

		#puts "#{expr1} => #{struct(expr1)}"
		#puts "#{expr2} => #{struct(expr2)}"

		s3 = struct(expr3)
		s3c = struct_compact(s3)
		#puts "3. #{expr3} => #{s3}"
		#puts "3. #{expr3} => #{s3c}"
		#puts "4. #{expr4} => #{struct_compact(struct(expr4))}"
		#puts "5. #{expr5} => #{struct_compact(struct(expr5))}"

		s6 = struct(expr6)
		s6c = struct_compact(s6)
		puts "6. #{expr6} => #{s6}"
		puts "		#{s6c}"
		puts "		#{expr_eval(s6c, vtable, ftable)}"
	end
end

#TMD::ExpressionEvaluator.test_retrieve_var
#TMD::ExpressionEvaluator.test_struct
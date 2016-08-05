P_OP = 1
P_CL = 2
MAP_OP = 3
MAP_CL = 4
ARR_OP = 5
ARR_CL = 6
QU_OP = 7
QU_CL = 8
SQ_OP = 9
SQ_CL = 10
QU = '"'
SQ = "'"

# Parses an argument list. See following formats:
#
# pre.
# (no-quotes-treated-as-string, another\ argument\ with\ escaped\ spaces)
# (nqtas, "double quotes", 'single quotes')
# ("string with ${varReplacement}")
# ({'key':val, 'hash':true})
# ([array, 1, 2, 3])
#
# Things to note:
# 
# # All values and keys are treated as strings, even if they're not enclosed;
# # Variable replacements only happen within quoted strings;
# 	# Replacements such as `"${var}"` will retain the type of the variable;
# # Whatever gets parsed as a value is valid for array values and hash key-value pairs.
def parse_args(arg_str)
	args = []
	state = [0]
	d = 0
	last_state = 0

	mkey = nil
	mval = nil

	tokens = arg_str.split(/(\(|\)|\{|\}|\[|\]}|"|'|\$|,|\\|:| )/)
	i = 0
	while i < tokens.length
		tok = tokens[i]
		i += 1

		if last_state == 0
			next if tok == '('
			if tok == '{'
				args << {}
				state[d] = MAP_OP
				last_state = MAP_OP
				d += 1
				state << 0
			elsif tok == '['
				args << []
				state[d] = ARR_OP
				last_state = ARR_OP
				d += 1
				state << 0
			elsif (tok == ',' || tok == ')') && last_state == 0
				if mval != nil
					args << mval
					mval = nil
				end
				if tok == ')'
					break
				end
			elsif tok == QU
				last_state = QU_OP
				mval = ''
			elsif tok == SQ
				last_state = SQ_OP
				mval = ''
			elsif tok.strip != ''
				mval = '' if !mval
				if tok == '\\'
					i += 1
					i += 1 if tokens[i] == ''
					mval += tokens[i]
					i += 1
				else
					mval += tok
				end
			end
		else
			if last_state == MAP_OP
				if state[d] == 0
					if tok == QU
						mkey = ''
						state[d] = QU_OP
					elsif tok == SQ
						mkey = ''
						state[d] = SQ_OP
					elsif tok == ':'
						mval = ''
					elsif tok == ',' || tok == '}'
						args[args.length-1][mkey] = mval
						mkey = nil
						mval = nil
						if tok == '}'
							state.pop
							d--
							last_state = 0
						end
					elsif tok.strip != '' && mval == nil
						mkey = '' if !mkey
						if tok == '\\'
							i += 1
							i += 1 if tokens[i] == ''
							mkey += tokens[i]
							i += 1
						else
							mkey += tok
						end
					elsif tok.strip != '' && mkey != nil
						if tok == '\\'
							i += 1
							i += 1 if tokens[i] == ''
							mval += tokens[i]
							i += 1
						else
							mval += tok
						end
					end
				elsif state[d] == QU_OP || state[d] == SQ_OP
					delim = state[d] == QU_OP ? QU : SQ
					if tok == '\\'
						i += 1
						i += 1 if tokens[i] == ''
						
						if mval == nil
							mkey += tokens[i]
						else
							mval += tokens[i]
						end
						i += 1
					elsif tok == delim
						state[d] = 0
					else
						if mval == nil
							mkey += tok
						else
							mval += tok
						end
					end
				end
			elsif last_state == ARR_OP
				if state[d] == 0
					if tok == QU
						mval = ''
						state[d] = QU_OP
					elsif tok == SQ
						mval = ''
						state[d] = SQ_OP
					elsif tok == ',' || tok == ']'
						args[args.length-1] << mval
						mval = nil
						if tok == ']'
							state.pop
							d--
							last_state = 0
						end
					elsif tok.strip != ''
						mval = '' if !mval
						if tok == '\\'
							i += 1
							i += 1 if tokens[i] == ''
							mval += tokens[i]
							i += 1
						else
							mval += tok
						end
					end
				elsif state[d] == QU_OP || state[d] == SQ_OP
					delim = state[d] == QU_OP ? QU : SQ
					if tok == '\\'
						i += 1
						i += 1 if tokens[i] == ''
						mval += tokens[i]
						i += 1
					elsif tok == delim
						state[d] = 0
					else
						mval += tok
					end
				end
			elsif last_state == QU_OP || last_state == SQ_OP
				delim = last_state == QU_OP ? QU : SQ
				if tok == '\\'
					i += 1
					i += 1 if tokens[i] == ''
					mval += tokens[i]
					i += 1
				elsif tok == delim
					state[d] = 0
					last_state = 0
				else
					mval += tok
				end
			end
		end
	end
	return args
end

arg_str = "({'a': b, \"c\": 5, 'd:12': this\\, has\\ a space}, [1, \"2\", \"${var}\"], \"hey dude \\\"gonzo\\\"\", literal\\ guantan)"
parse_args(arg_str)
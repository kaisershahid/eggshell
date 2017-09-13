module Eggshell; class ExpressionEvaluator;
module Parser
	ST_NULL = 0
	ST_NUM = 1
	ST_STRING = 2
	ST_STRING_EMBED = 4
	ST_STRING_BLOCK = 8
	ST_LABEL = 16
	ST_LABEL_CALL = 17
	ST_LABEL_MEMBER = 19
	ST_OPERATOR = 32
	ST_OPERATOR_TERN = 33
	ST_GROUP = 64
	ST_HASH = 128
	ST_ARRAY = 256
	ST_INDEX_ACCESS = ST_ARRAY|ST_LABEL
	
	STATE_NAMES = {
		0 => 'null',
		1 => 'number',
		2 => 'string',
		4 => 'string_expression',
		8 => 'string_block',
		16 => 'label',
		17 => 'label_call',
		19 => 'label_member',
		32 => 'operator',
		33 => 'operator_tern',
		64 => 'group',
		128 => 'hash',
		256 => 'array',
		ST_INDEX_ACCESS => 'index_access'	
	}.freeze
	
	CONSTS = {
		'true' => true,
		'false' => false,
		'nil' => nil,
		'null' => nil
	}.freeze
	
	# Indicates only one statement allowed
	FL_ONE_STATEMENT = 1
	# Indicates that for an opening brace (e.g. `if (...) {`), collect remaining items after brace. 
	FL_BRACE_OP_COLLECT = 2

	# Builds a parse tree from the lexer.
	class DefaultParser
		def initialize()
			@lexer = Eggshell::ExpressionEvaluator::Lexer.new(self)
		end

		def reset()
			@tree = []
			@ptr = @tree
			@last_ptr = [@tree]
			@tokens = []
			@state = [ST_NULL]
			@term_last = [nil]
			@term_str = nil
			@quote_delim = nil
			@word_pos = 0
			@expect_label = false
			@array_state = [0]
			@hash_state = [nil]
			@last_comma = false
		end

		def emit(type, data = nil, ts = nil, te = nil)
			lst = @state[-1]
			# pop last state if appropriate
			if type == :end
				while @state[-1] == ST_OPERATOR || @state[-1] == ST_OPERATOR_TERN
					@state.pop
				end
				return
			end

			word = data[ts...te].pack('c*')
			@tokens << word # if type != :space
			
			# before inserting term, need to make sure it follows semantics of function/array
			# @todo look out for case of '(,' or '[,'
			arg_check = true
			if lst == ST_LABEL_CALL
				arg_check = @ptr.length == 0 || @last_comma
			elsif lst == ST_ARRAY
				arg_check = @ptr.length == 1 || @last_comma
			end
			#arg_check = arg_check && (@hash_state[-1] == :colon || @hash_state[-1] == :comma)
			@last_comma = false if type != :space
			
			expr_frag = ''
			if @tokens.length > 5
				expr_frag = @tokens[@tokens.length-5..-2].join('')
			else
				expr_frag = @tokens[0..-2].join('')
			end

			# @todo need to track last literal/var/func for operator syntax check
			if type == :escape
				raise Exception.new("expecting identifier after '#{@ptr[-1][1]}'") if @expect_label
				raise Exception.new("escaping character outside of string") if lst != ST_STRING
				word_unesc = ESCAPE_MAP[word]
				raise Exception.new("invalid escape sequence: #{word}") if !word_unesc

				@term_str += word_unesc
				return
			elsif type == :str_delim
				raise Exception.new("expecting identifier after '#{@ptr[-1][1]}', not #{word}") if @expect_label
				if !@quote_delim
					@term_last.pop if lst != ST_INDEX_ACCESS
					raise Exception.new("missing a comma after: #{expr_frag}") if !arg_check
					if @hash_state[-1] == :key
						@hash_state[-1] = :colon
					elsif @hash_state[-1] == :value
						@hash_state[-1] = :comma
					elsif @hash_state[-1] == :comma
						raise Exception.new("expecting comma after: #{expr_frag}")
					end
					@quote_delim = word
					@state << ST_STRING
					@term_str = ''
				elsif @quote_delim == word
					@quote_delim = nil
					@state.pop
					@ptr << @term_str
					@term_str = nil
				end
			elsif lst == ST_STRING
				@term_str += word
			elsif type == :number_literal
				@term_last.pop if lst != ST_INDEX_ACCESS
				raise Exception.new("expecting identifier after: '#{@ptr[-1][1]}'") if @expect_label
				raise Exception.new("missing a comma after: #{expr_frag}") if !arg_check
				@ptr << (word.index('.') ? word.to_f : word.to_i)

				if @hash_state[-1] == :key
					@hash_state[-1] = :colon
				elsif @hash_state[-1] == :value
					@hash_state[-1] = :comma
				end
			elsif type == :identifier
				if lst == ST_LABEL_MEMBER
					@state.pop
					@ptr << word
					@last_ptr[-1][-1] << @ptr
					@ptr = @last_ptr.pop
				elsif @expect_label
					@ptr[-1][1] += word
					@expect_label = false
				else
					raise Exception.new("missing a comma after: #{expr_frag}") if !arg_check
					
					if CONSTS.has_key?(word)
						@ptr << CONSTS[word]
					else
						@ptr << [:var, word]
					end

					if @hash_state[-1] == :key
						@hash_state[-1] = :colon
					elsif @hash_state[-1] == :value
						@hash_state[-1] = :comma
					end
				end
				@term_last << ST_LABEL
			elsif type == :logical_op
				# STORED AS: `[:op, [operand1, operator1, operand2, operator2, ...]]
				# > @last_ptr holds entire structure, @ptr holds structure[1]
				# @todo deal with '-' prefix
				
				# direct assignment unsupported for now, cast to equivalence
				word = '==' if word == '='
				@term_last.pop
				raise Exception.new("expecting identifier after '#{@ptr[-1][1]}'") if @expect_label
				if word == '?'
					tern = [:op_tern, nil, [], nil]
					tern[1] = @last_ptr[-1].pop
					@last_ptr[-1] << tern
					@ptr = tern[2]
					@state[-1] = ST_OPERATOR_TERN
				elsif lst == ST_OPERATOR
					op = word.to_sym
					prec_l = OPERATOR_MAP[@ptr[-2]]
					prec_r = OPERATOR_MAP[op]

					if prec_r > prec_l
						# need to group next 2 terms since this operator has higher precedence
						nop = [:op, [@ptr.pop]]
						@state << ST_OPERATOR
						@ptr << nop
						@last_ptr << @ptr
						@ptr = nop[1]
					elsif prec_l > prec_r
						# check if @last_ptr[-1] is an op; pop if so
						type = @last_ptr[-2].is_a?(Array) ? @last_ptr[-2][0][0] : nil
						if type == :op
							@state.pop
							@last_ptr.pop
							@ptr = @last_ptr[-1][0][1]
						end
					end
					@ptr << op
				else
					lele = @ptr.pop
					op = [:op, [lele, word.to_sym]]
					@last_ptr << @ptr
					@ptr << op
					@ptr = op[1]
					@state << ST_OPERATOR
				end
			elsif type == :paren_group
				# STORED AS: [:group, [nested_statement]]
				# STORED AS: [:func, 'funcname', [args*]]
				raise Exception.new("expecting identifier after '#{@ptr[-1][1]}'") if @expect_label
				if word == '('
					if @term_last[-1] == ST_LABEL
						@state << ST_LABEL_CALL
						@ptr[-1][0] = :func
						@ptr[-1][2] = []
						
						@last_ptr << @ptr
						@ptr = @ptr[-1][2]
						@expect_separator = ','
					else
						raise Exception.new("missing a comma after: #{expr_frag}") if !arg_check
						@state << ST_GROUP
						@last_ptr << @ptr
						@ptr << [:group, []]
						@ptr = @ptr[-1][1]
					end
					@term_last.pop
				else
					do_close = false
					if lst == ST_OPERATOR
						do_close = @state[-2] == ST_GROUP
						if do_close
							@state.pop
							@ptr = @last_ptr.pop[1]
						end
					else
						do_close = lst == ST_LABEL_CALL || lst == ST_GROUP
					end
						
					if do_close
						s = @state.pop
						@ptr = @last_ptr.pop
						@expect_separator = nil

						if @hash_state[-1] == :key
							@hash_state[-1] = :colon
						elsif @hash_state[-1] == :value
							@hash_state[-1] = :comma
						end
					else
						# @todo exception
					end
				end
			elsif type == :brace_group
				raise Exception.new("missing a comma after: #{expr_frag}") if !arg_check
				if word == '{'
					if @hash_state[-1] && @hash_state[-1] != :value
						raise Exception.new("invalid hash start")
					end

					@state << ST_HASH
					@last_ptr << @ptr
					@ptr = [:hash]
					@hash_state << :key
				else
					if lst == ST_HASH
						if @hash_state[-1] != :comma
							msg = "missing value for key #{@ptr[-1]}"
							msg = "missing ':' and a value for key #{@ptr[-1]}" if @hash_state[-1] == :key
							msg = "missing a value for key #{@ptr[-1]}" if @hash_state[-1] == :value
							raise Exception.new(msg)
						end

						@last_ptr[-1] << @ptr
						@ptr = @last_ptr.pop
						@state.pop
						@hash_state.pop

						if @hash_state[-1] == :key
							@hash_state[-1] = :colon
						elsif @hash_state[-1] == :value
							@hash_state[-1] = :comma
						end
					else
						# @todo throw exception
					end
				end
			elsif type == :index_group
				if word == '['
					if @term_last[-1] == ST_LABEL
						@state << ST_INDEX_ACCESS
						@last_ptr << @ptr
						@ptr = [:index_access]
					else
						raise Exception.new("missing a comma after: #{expr_frag}") if !arg_check
						# @todo check if array being defined within index_access
						if @hash_state[-1] && @hash_state[-1] != :value
							raise Exception.new("invalid array start near: #{expr_frag}")
						end

						@ptr << [:array]
						@state << ST_ARRAY
						@last_ptr << @ptr
						@ptr = @ptr[-1]
					end
				else
					if lst == ST_INDEX_ACCESS
						acc = @ptr
						@ptr = @last_ptr.pop
						@ptr[-1] << acc
						@state.pop
					elsif lst == ST_ARRAY
						@ptr = @last_ptr.pop
						@state.pop

						if @hash_state[-1] == :key
							@hash_state[-1] = :colon
						elsif @hash_state[-1] == :value
							@hash_state[-1] = :comma
						end
					else
						# @todo throw exception
					end
				end
			elsif type == :separator
				# @todo need to ensure proper separation!!!
				if word == '.'
					if @term_last[-1] == ST_LABEL
						@state << ST_LABEL_MEMBER
						@last_ptr << @ptr
						@ptr = [:member_access]
					else
						# @todo throw exception
					end
				elsif word == ','
					if lst == ST_HASH
						if @hash_state[-1] == :comma
							@hash_state[-1] = :key
						else
							raise Exception.new("misplaced comma near: #{expr_frag}")
						end
					elsif lst == ST_ARRAY
						@last_comma = true
					elsif lst == ST_LABEL_CALL
						@last_comma = true
					end
				elsif word == ';'
				end
			elsif type == :modifier
				if word == ':'
					if lst == ST_HASH
						if @hash_state[-1] == :colon
							@hash_state[-1] = :value
						else
							raise Exception.new("misplaced colon near: #{expr_frag} -- #{@hash_state[-1]}")
						end
					elsif lst == ST_OPERATOR_TERN
						# assumes [:op_tern, cond, true, false] structure
						tern = @last_ptr[-1][-1]
						if tern[3] == nil
							tern[3] = []
							@ptr = tern[3]
						else
							# @todo throw exception. more than 1 ':' encountered
						end
					elsif @term_last[-1] == ST_LABEL
						@ptr[-1][1] += ':'
						@expect_label = true
						@term_last[-1] = nil
					end
				end
			elsif type == :space
			else
				$stderr.write "! parser else: #{word}\n"
			end
		end
		
		def parse(src, flags = 0)
			reset
			begin
				@lexer.process(src)
				emit(:end)
				if @state[-1] != ST_NULL
					err = []
					@state[1..-1].each do |st|
						err << STATE_NAMES[st]
					end
					raise Exception.new("Unbalanced state: #{err.join(' -> ')}")
				end
				@tree
			rescue Exception => ex
				$stderr.write("WARN: returning nil, parse exception for: #{src}\n#{ex}\n")
				$stderr.write("\t#{ex.backtrace.join("\n\t")}\n")
				debug
				nil
			end
		end
		
		def debug(io = nil)
			io = $stderr if !io
			io.write "STATE : "
			@state.each do |st|
				io.write STATE_NAMES[st]
				io.write ", "
			end
			io.write "\n"
			io.write "TREE  : #{@tree.inspect}\n"
			io.write "  PTR : #{@ptr.inspect}\n"
			io.write "TOKENS: #{@tokens.inspect}\n"
		end
	end
	
	def self.reassemble(struct, sep = '')
		buff = []
		s = ''
		struct.each do |ele|
			if ele.is_a?(Array)
				if ele[0] == :op
					buff << reassemble(ele[1])
				elsif ele[0] == :op_tern
					buff << reassemble(ele[1])
					buff << ' ? '
					buff << reassemble(ele[2])
					buff << ' : '
					buff << reassemble(ele[3])
				elsif ele[0] == :func
					buff << ele[1] + '('
					buff << reassemble(ele[2], ',')
					buff << ')'
				elsif ele[0] == :group
					buff << '('
					buff << reassemble(ele[1..-1])
					buff << ')'
				elsif ele[0] == :var
					if ele.length > 2
						buff << reassemble(ele[1..-1])
					else
						buff << ele[1]
					end
				elsif ele[0] == :index_access
					buff << '['
					if ele[1].is_a?(Array)
						buff << reassemble(ele[1])
					else
						buff << ele[1]
					end
					buff << ']'
				end
			else
				buff << s
				buff << (ele.is_a?(String) ? '"' + ele.gsub('"', '\\"') + '"' : ele)
				s = sep
			end
		end
		
		buff.join('')
	end
end
end; end;
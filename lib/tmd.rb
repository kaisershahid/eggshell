# TechnicalMarkDown
module TMD
	COLLECT = 1
	DONE = 2

	module MacroHandler
		def set_parser(tmd)
		end

		def process(buffer, macname, args, lines, indent)
 	 	end

 	 	class NoOpHandler
 	 		include MacroHandler

 	 		def set_parser(tmd)
 	 			@tmd = tmd
 	 		end

 	 		def process(buffer, macname, args, lines, indent)
 	 			@tmd._warn("couldn't find macro: #{macname}")
 	 		end
 	 	end
	end

	# For complex nested content, use the block to execute content correctly.
	# Quick examples: nested loops, conditional statements.
	class Block
		def initialize(macro, handler, args, depth)
			@stack = [self]
			@lines = []
			@macro = macro
			@handler = handler
			@args = args
			@delim = @args.pop.strip

			# reverse, and swap out
			if @delim[0] == '{'
				@delim = @delim.reverse.gsub(/\{/, '}')
			else
				@delim = nil
			end

			@depth = depth
		end

		attr_reader :depth, :lines, :delim

		def cur
			@stack[@stack.length-1]
		end

		def push(block)
			@stack << block
			@lines << block
		end

		def pop()
			@stack.pop
		end

		def collect(entry)
			@stack[@stack.length-1].lines << entry
		end

		def process(buffer)
			@handler.process(buffer, @macro, @args, @lines, @depth)
		end

		def inspect
			"<BLOCK #{@macro} (#{@depth}) #{@handler} >"
		end
	end

	class Processor
		def initialize
			@vars = {:references => {}, :toc => [], :include_paths => [], 'log.level' => '1'}
			@macros = {}

			defhandler = TMD::MacroHandler::Defaults::MHBasics.new
			defhandler.set_parser(self)

			ctrlhandler = TMD::MacroHandler::Defaults::MHControlStructures.new
			ctrlhandler.set_parser(self)
		end

		def register_macro(handler, *macros)
			macros.each do |mac|
				@macros[mac] = handler
			end
		end

		def _error(msg)
			$stderr.write("[ERROR] #{msg}\n")
		end

		def _warn(msg)
			$stderr.write("[WARN]  #{msg}\n")
		end

		def _info(msg)
			return if @vars['log.level'] < '1'
			$stderr.write("[INFO]  #{msg}\n")
		end

		def _debug(msg)
			return if @vars['log.level'] < '2'
			$stderr.write("[DEBUG] #{msg}\n")
		end

		def _trace(msg)
			return if @vars['log.level'] < '3'
			$stderr.write("[TRACE] #{msg}\n")
		end

		attr_reader :vars

		# Expands expressions within `\${}`. Currently only inserts variables by key.
		def parse_expr(expr)
			# replace dynamic placeholders
			# @todo expand to actual expressions
			buff = []
			esc = false
			exp = false
			expr.split(/(\\|\$\[|\$\{|\]|\})/).each do |ele|
				if ele == '\\'
					esc = true
					next
				elsif ele == ''
					next
				end

				if esc
					buff << ele
					esc = false
					next
				end

				if ele == '$[' || ele == '${'
					exp = true
				elsif exp && (ele == ']' || ele == '}')
					exp = false
				elsif exp
					buff << @vars[ele]
				else
					buff << ele
				end
			end

			return buff.join('')
		end

		REGEX_EXPR_PLACEHOLDERS = /(\\|\$\[|\$\{|\]|\}|\+|\-|>|<|=|\s+|\(|\)|\*|\/`)/
		REGEX_EXPR_STATEMENT = /(\(|\)|,|\[|\]|\+|-|\*|\/|%|<=|>=|==|<|>|"|'|\s+)/

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
			'&&' => 45,
			'||' => 44
		}.freeze

		# Normalizes a term.
		# @param Object term If `String`, attempts to infer type (either `Fixnum`, `Float`, or `[:var, varname]`)
		def term_val(term)
			if term.is_a?(String)
				if term.match(/^\d+$/)
					return term.to_i
				elsif term.match(/^\d*\.\d+$/)
					return term.to_f
				end
				return [:var, term]
			end
			return term
		end

		# Inserts a term into the right-most operand.
		# 
		# Operator structure: `[:op, 'operator', 'left-term', 'right-term']
		def op_insert(frag, term)
			while frag[3].is_a?(Array)
				frag = frag[3]
			end
			frag[3] = term_val(term)
		end

		# Restructures operands if new operator has higher predence than previous operator.
		# @param String tok New operator.
		# @param Array frag Operator fragment.
		# @param Array stack Fragment stack.
		def op_precedence(tok, frag, stack)
			_trace "... OP_PRECEDENCE pre: #{frag.inspect}", LOG_OP
			topfrag = frag
			lptr = nil
			# retrieve the right-most operand
			while frag[3].is_a?(Array) && frag[3][0] == :op
				lptr = frag
				frag = frag[3]
			end
			lptr = topfrag if !lptr
			_trace ">>> lptr = #{lptr.inspect}, frag = #{frag.inspect}", LOG_OP

			if frag[0] == :op
				p1 = OP_PRECEDENCE[tok]
				p0 = OP_PRECEDENCE[frag[1]]
				_trace "??? check OP_PRECEDENCE (#{tok} #{p1}, #{frag[1]} #{p0}", LOG_OP
				if p1 > p0
					_trace "^^^ bump up #{tok}", LOG_OP
					frag[3] = [:op, tok, frag[3], nil]
				else
					_trace "___ no bump #{tok} (lptr = #{lptr.inspect}", LOG_OP
					lptr[3] = [:op, tok, [:op, frag[1], frag[2], frag[3]], nil]
				end
				stack << topfrag
				_trace "... new frag: #{frag.inspect} || #{stack.inspect}", LOG_OP
			else
				_trace "<<< frag op.2b: stack = #{stack.inspect}", LOG_OP
				stack << [:op, tok, frag, nil]
			end
		end

		def expr_struct(str)
			puts "START: #{str}"
			toks = str.split(REGEX_EXPR_STATEMENT)
			state = [:nil]
			d = 0

			# each element on the stack points to a nested level (so root is 0, first parenthesis is 1, second is 2, etc.)
			# ptr points to the deepest level
			stack = [[]]
			ptr = stack[0]
			term = nil

			i = 0
			while (i < toks.length)
				tok = toks[i]
				i += 1
				next if tok == ''

				if tok.match(/\+|-|\*|\/|%|<=|>=|<|>|==|!=|&&|\|\||&|\|/)
					_trace "** op: #{tok} -> #{term} (d=#{d})", LOG_OP
					_trace "\t..ptr = #{ptr.inspect} (stack.length = #{stack.length})", LOG_OP
					state << :op
					d += 1
					if term
						if ptr.length == 0
							ptr << [:op, tok, term_val(term), nil]
							term = nil
							_trace "frag op.0: #{ptr[-1].inspect}", LOG_OP
						else
							# @TODO this doesn't make sense. if there's a dangling term then there's a syntax error
							# ... x + y z - a ==> 'z' would be the term before '-' for something like this to happen
							last = ptr.pop
							ptr << [:op, tok, last, term]
							_trace "frag op.1: #{ptr[-1].inspect}", LOG_OP
						end
					else
						if ptr.length > 0
							_trace "frag op.2 (d=#{d})...", LOG_OP
							frag = ptr.pop
							# when you have x + y / ..., make it x + (y / ...)
							_trace "frag op.2: #{tok} -- #{frag.inspect}", LOG_OP
							op_precedence(tok, frag, ptr)
						end
					end
					_trace' ** OP DONE **', LOG_OP
				elsif tok == '('
					if term
						_trace'push fn ('
						ptr << [:fn, term, []]
						term = nil
						state << :fnop
						d += 1
						arr = []
						stack << arr
						ptr = arr
					else
						_trace'push nest ('
						state << :nest
						d += 1
						arr = []
						stack << arr
						ptr = arr
					end
					_trace "...... #{stack.inspect}"
				elsif tok == ')'
					lstate = state.pop
					lstack = stack.pop
					ptr = stack[-1]
					d = state.length - 1
					_trace "/#{lstate} ) (d=#{d}, lstack=#{lstack.inspect}"
					_trace "\tstate = #{state.inspect}"
					_trace "\tstack = #{stack.inspect} ===> ptr=#{ptr.inspect}"

					if lstate == :nest
						if state[d] == :fnop
							lstack.each do |item|
								ptr << item
							end
						else
							frag = ptr[-1]
							if frag
								op_insert(frag, lstack)
							else
								lstack.each do |item|
									_trace "#{d}: reinserting #{item.inspect}"
									ptr << item
								end
							end
						end
					elsif lstate == :fnop
						if term
							_trace "last term: #{term}"
							lstack << term
							term = nil
						end
						_trace "\tptr=#{ptr.inspect}"
						ptr[-1][2] = lstack
						#ptr = lstack
					end
				elsif tok == ','
					_trace ",, (state = #{state.inspect}"
					if state[d-1] == :fnop
						if term
							ptr << term
							term = nil
						end
					end
				#elsif tok == '#'
				#elsif tok == "'"
				elsif tok.strip != ''
					_trace "tok: #{tok} (d=#{d}) ==> ptr=#{ptr.inspect}"
					_trace "\tstate=#{state.inspect}"
					_trace "\tstack=#{stack.inspect}"
					#_trace "\tstate = #{state.inspect}"
					term = term ? term + tok : tok

					if state[d] == :op
						if ptr[-1] == nil
							# @throw exception
						elsif ptr[-1][0] == :op
							frag = ptr[-1]
							op_insert(frag, term)
							term = nil
						else
							# ???
						end
						state.pop
						d -= 1
					elsif state[d-1] == :fnop
						_trace "**** fnop arg: #{term} (#{state[d]}"
						ptr << term
						term = nil
						next
					end
				end
			end

			if state[d] == :op && term
				_trace "term: #{term} ==> #{ptr.inspect}"
				frag = ptr[-1]
				if frag[0] == :op
					op_insert(frag, term)
				end
			end

			#inspect(stack[0])
			#puts "STACK: #{stack[0].inspect}"
			return stack[0]
		end

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
		#
		# @param Boolean keep_end If true, returns the unparsed portion of the argument
		# string (even if it's empty). This can be used to determine custom delimiters.
		# @return Array Argument values. Last value is the remaining portion of the initial string.
		# @todo handle `arg1, arg2 {` (e.g. no parenthesis enclosing args)
		def parse_args(arg_str, keep_end = false)
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
							args << parse_expr(mval)
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
								args[args.length-1][mkey] = parse_expr(mval)
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
								args[args.length-1] << parse_expr(mval)
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
							args << mval
							mval = nil
						else
							mval += tok
						end
					end
				end
			end

			if last_state == MAP_OP && mkey && mval
				args[args.length-1][mkey] = mval
			elsif last_state == ARR_OP && mval
				args[args.length-1] << mval
			elsif mval
				args << mval
			end

			if keep_end
				args << tokens[i..tokens.length].join('')
			end

			_trace "parse_args(#{arg_str}, #{keep_end}): #{args.inspect}"
			return args
		end

		TAB = "\t"
		TAB_SPACE = '    '

		# Iterates through each line of a source document and processes block-level items
		# @param Fixnum call_depth For macro processing. Allows accurate tracking of nested
		# block macros.
		def process(lines, call_depth = 0)
			buff = []
			order_stack = []
			otype_stack = []
			in_table = false
			in_html = false
			end_html = nil
			in_block = false
			in_dl = false

			capturing = false
			cap_buff = nil
			cap_var = nil

			macro = nil
			macro_blocks = []
			macro_handler = nil

			block = nil
			ext_line = nil

			lines.each do |line|
				if line.is_a?(Block)
					line.process(buff)
					next
				end

				line = line.rstrip
				# if line end in \, buffer and continue to next line;
				# join buffered line once \ no longer at end
				if line[-1] == '\\' && line[-2] != '\\'
					if ext_line
						ext_line += line[0...line.length-1]
					else
						ext_line = line[0...line.length-1]
					end
					next
				elsif ext_line
					line = ext_line + line
					ext_line = nil
				end
				oline = line

				indent = 0
				if line[0] == TAB || line[0..3] == TAB_SPACE
					tab = line[0] == TAB ? TAB : TAB_SPACE
					offset = tab.length
					indent += 1
					while line.index(tab, offset)
						indent += 1
						offset += tab.length
					end
					line = line[offset..line.length]
				end

				# macro processing
				if line[0] == '@'
					idx = line.index('(')
					idx = line.index(' ') if !idx
					idx = line.length if !idx

					macro = line[1..idx-1].strip
					args = line[idx..line.length]
					macro_handler = @macros[macro]
					if macro_handler
						macro_depth = call_depth + indent
						args = parse_args(args, true)
						if args[-1].index('{')
							if block
								nblock = Block.new(macro, macro_handler, args, block.cur.depth + 1)
								block.push(nblock)
							else
								block = Block.new(macro, macro_handler, args, macro_depth)
							end
						else
							args.pop
							macro_handler.process(buff, macro, args, nil, macro_depth)
						end
					else
						_warn("macro not found: #{macro}")
					end
					next
				elsif block
					if line == block.cur.delim
						lb = block.pop
						if !block.cur
							block.process(buff)
							block = nil
						end
					else
						block.collect(oline)
					end
					next
				end

				if line[0] == '!'
					next if line[1] == '#'
					#v, k = line[1..line.length].split(/:\s*/, 2)
					#@vars[v] = k
					#next
				end

				# html block processing
				html = line.match(HTML_BLOCK)
				if html
					end_html = "</#{html[1]}>$"
					if !line.match(end_html)
						in_html = true
					end

					line = $tmd.parse_expr(line) if !@vars['html.no_eval']
					buff << line
					@vars.delete('html.no_eval')

					next
				elsif in_html
					buff << line
					if line.match(end_html)
						in_html = false
						end_html = nil
					end
					next
				end

				# header block processing
				# @todo support attributes
				hdr = line.match(/^(h\d)\. (.+)/)
				if hdr
					id = hdr[2].downcase.strip.gsub(/[^a-z0-9_-]+/, '-')
					buff << "<#{hdr[1]} id='#{id}'>#{hdr[2]}</#{hdr[1]}>"
					next
				end

				# list block processing
				if line[0] == '-' || line[0] == '#'
					type = line[0] == '-' ? 'ul' : 'ol'
					if order_stack.length == 0
						order_stack << "<#{type}>"
						otype_stack << type
					# @todo make sure that previous item was a list
					# remove closing li to enclose sublist
					elsif indent > (otype_stack.length-1) && order_stack.length > 0
						last = order_stack[order_stack.length-1]
						last = last[0...last.length-5]
						order_stack[order_stack.length-1] = last

						order_stack << "#{"\t"*indent}<#{type}>"
						otype_stack << type
					elsif indent < (otype_stack.length-1)
						count = otype_stack.length - 1 - indent
						while count > 0
							ltype = otype_stack.pop	
							order_stack << "#{"\t"*count}</#{ltype}>\n#{"\t"*(count-1)}</li>"
							count -= 1
						end
					end
					order_stack << "#{"\t"*indent}<li>#{fmt_line(line[1...line.length].strip)}</li>"
					next
				end

				# table block processing
				# @todo support |< syntax
				if line[0] == '/' || line[0] == '|' || line[0] == '\\'
					if !in_table
						in_table = true
						@vars['t.row'] = 0
						buff << "<table class='#{@vars['table.class']}' style='#{@vars['table.style']}' #{@vars['table.attribs']}>"
					end

					cols = []
					if line[0] == '/'
						cols = line[1..line.length].split('|')
						buff << '<tr>'
						cols.each do |col|
							buff << "\t#{fmt_cell(col, true)}"
						end
						buff << '</tr>'
					elsif line[0] == '|' || line[0..1] == '|>'
						idx = 1
						sep = '|'
						if line[1] == '>'
							idx = 2
							sep = '|>'
						end
						cols = line[idx..line.length].split(sep)
						@vars['t.row'] += 1
						buff << '<tr>'
						cols.each do |col|
							buff << "\t#{fmt_cell(col)}"
						end
						buff << '</tr>'
					else
						# @todo process footer
						buff << "</table>"
						@vars['table.class'] = ''
						@vars['table.style'] = ''
						@vars['table.attribs'] = ''
						in_table = false
					end
					next
				end

				if line[0..1] == '>>'
					if !in_dl
						in_dl = true
						buff << "<dl class='#{@vars['dd.class']}'>"
					end
					key, val = line[2..line.length].split('::', 2)
					key = fmt_line(key)
					val = fmt_line(val)
					#$stderr.write "dl: #{key} => #{val}\n"
					buff << "<dt class='#{@vars['dt.class']}'>#{key}</dt><dd class='#{@vars['dd.class']}'>#{val}</dd>"
					next
				end

				if line == ''
					if in_dl
						buff << '</dl>'
						in_dl = false
					elsif order_stack.length > 0
						d = otype_stack.length
						c = 1
						otype_stack.each do |type|
							ident = d - c
							order_stack << "#{"\t" * ident}</#{type}>#{c == d ? '' : "</li>"}"
							c += 1
						end
						buff << order_stack.join("\n")
						order_stack = []
						otype_stack = []
					elsif in_table
						in_table = false
						buff << '</table>'
					elsif in_block
						buff << '</p>'
						in_block = false
					end
				else
					if !in_block
						in_block = true
						buff << "<p class='#{@vars['p.class']}'>"
					elsif in_block
						if line[-1] != '\\'
							buff << '<br />'
						end
					end
					buff << fmt_line(line)
				end
			end

			# @todo how to clean up dangler?
			if ext_line
				line = ext_line
			end

			# close out
			if in_dl
				buff << '</dl>'
				in_dl = false
			elsif order_stack.length > 0
				d = otype_stack.length
				c = 1
				otype_stack.each do |type|
					ident = d - c
					order_stack << "#{"\t" * ident}</#{type}>#{c == d ? '' : "</li>"}"
					c += 1
				end
				buff << order_stack.join("\n")
				order_stack = []
				otype_stack = []
			elsif in_table
				in_table = false
				buff << '</table>'
			elsif in_block
				buff << '</p>'
				in_block = false
			end

			return buff.join("\n")
		end

		HASH_FMT_DECORATORS = {
			'[*' => '<b>',
			'[**' => '<strong>',
			'[_' => '<i>',
			'[__' => '<em>',
			'*]'=> '</b>',
			'**]' => '</strong>',
			'_]' => '</i>',
			'__]' => '</em>',
		}.freeze

		HASH_HTML_ESCAPE = {
			"'" => '&#039;',
			'"' => '&quot;',
			'<' => '&lt;',
			'>' => '&gt;',
			'&' => '&amp;'
		}.freeze

		# html tags that have end-block checks. any block starting with one of these tags will have
		# its contents passed through until end of the tag
		HTML_BLOCK = /^<(p|div|style|script|blockquote|pre)/

		# @todo more chars
		def html_escape(str)
			return str.gsub(/("|'|<|>|&)/, HASH_HTML_ESCAPE)
		end

		# Expands markup for a specific line.
		def fmt_line(expr)
			buff = []
			bt = false
			br = 0
			cd = false
			an = false
			im = false

			# split and preserve delimiters: ` {{ }} [[ ]]
			# - preserve contents of code blocks (only replacing unescaped placeholder values)
			## - handle anchor and image
			expr.split(/(`|\{\{|\}\}|\[\[|\]\])/).each do |part|
				if part == '`' && !cd
					if !bt
						bt = true
						buff << "<code class='tick'>"
					else
						bt = false
						buff << '</code>'
					end
				elsif part == '{{' && !bt
					cd = true
					buff << "<code class='norm'>"
				elsif part == '}}' && !bt
					buff << '</code>'
					cd = false
				elsif bt || cd
					buff << html_escape(parse_expr(part))
				elsif part == '[['
					# open link or image
					tok = nil
					if buff.length == 0
						an = true
					else
						last = buff[buff.length-1]
						if last.length == 0
							tok = ''
						else
							tok = last[-1]
						end
					end

					if tok == ' ' || tok == '' || tok == '>'
						an = true
					else
						buff << '[['
					end
				elsif part == ']]' && (im || an)
					im = false
					an = false
				elsif an
					if part[0] == '!'
						part = part[1..part.length]
						im = true
						an = false
					end

					if an
						href, text, attribs = part.split('|', 3)
						buff << "<a href='#{html_escape(href)}' #{attribs}>#{text}</a>"
					else
						comps = part.split('|', 5)
						src = comps.shift
						atts = ["src='#{html_escape(src)}'"]
						href = nil
						aattribs = nil
						comps.each do |comp|
							if comp.match(/^(\d+x?\d*|\d*x\d+)$/)
								w, h = comp.split('x')
								atts << "width='#{w}'" if w != ''
								atts << "height='#{h}'" if h && h != ''
							elsif comp[0] == '>'
								href, aattribs = comp[1..comp.length].split('|', 2)
							elsif comp.match(/\w+=/)
								atts << comp
							else
								atts << "title='#{html_escape(comp)}'"
							end
						end

						if href
							buff << "<a href='#{html_escape(href)}' #{aattribs}>"
						end
						buff << "<img #{atts.join(' ')} />"
						if href
							buff << "</a>"
						end
					end
				else
					part = part.gsub(/(\[\*{1,2}|\*{1,2}\]|\[_{1,2}|_{1,2}\])/, HASH_FMT_DECORATORS)

					# handle sub & sup scripts specially. if prefixed with '!', resolve and link to internal footnote
					part = part.gsub(/\/\^(.+)\^\//) do |match|
						el = $1
						ref = nil
						if el[0] == '!'
							el = el[1..el.length]
							ref = ref_find(el)
						end

						if ref
							"<sup><a href='##{ref[:anchor]}'>#{el}</a></sup>"
						else
							"<sup>#{el}</sup>"
						end
					end

					part = part.gsub(/\/_(.+)_\//) do |match|
						el = $1
						ref = nil
						if el[0] == '!'
							el = el[1..el.length]
							ref = ref_find(el)
						end

						if ref
							"<sub><a href='##{ref[:anchor]}'>#{el}</a></sub>"
						else
							"<sub>#{el}</sub>"
						end
					end

					buff << part
				end
			end

			return parse_expr(buff.join(''))
		end

		def fmt_cell(val, header = false)
			tag = header ? 'th' : 'td'
			buff = []
			attribs = ''
			if val[0] == '!'
				rt = val.index('!', 1)
				attribs = val[1...rt]
				val = val[rt+1..val.length]
			end

			buff << "<#{tag} #{attribs}>"
			if val[0] == '\\'
				val = val[1..val.length]
			end

			buff << fmt_line(val)
			buff << "</#{tag}>"
			return buff.join('')
		end

		# Adds a reference. Example formats:
		#
		# <pre>
		# Smith, John. 
		# #key Smith, John.
		# </pre>
		def ref_add(line)
		end

		def ref_find(el)
			if @vars[:references][el]
				return @vars[:references][el]
			end
		end
	end
end

require_relative './tmd/macro-handler.rb'
require_relative './tmd/block-handler.rb'
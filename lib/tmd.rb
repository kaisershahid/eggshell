# TechnicalMarkDown
module TMD
	COLLECT = 1
	DONE = 2

	module MacroHandler
		def set_parser(tmd)
		end

		def start(macname, args, depth, buffer)
		end

		def collect(line, depth)
		end

		def finish(macname, depth)
		end

		def process(buffer, macname, args, lines, indent)
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
			@vars = {:references => {}, :toc => [], :include_paths => [], 'log' => '1'}
			@macros = {}

			defhandler = TMD::MacroHandler::Defaults::MHBasics.new
			defhandler.set_parser(self)
			@macros['var'] = defhandler
			@macros['include'] = defhandler
			@macros['capture'] = defhandler
			@macros['parse_test'] = defhandler

			ctrlhandler = TMD::MacroHandler::Defaults::MHControlStructures.new
			ctrlhandler.set_parser(self)
			@macros['loop'] = ctrlhandler
			@macros['for'] = ctrlhandler
			@macros['if'] = ctrlhandler
			@macros['else'] = ctrlhandler
		end

		def register_macro(handler, *macros)
			handler.set_parser(self)
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
			return if @vars['log'] < '1'
			$stderr.write("[INFO]  #{msg}\n")
		end

		def _debug(msg)
			return if @vars['log'] < '2'
			$stderr.write("[DEBUG] #{msg}\n")
		end

		def _trace(msg)
			return if @vars['log'] < '3'
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
					v, k = line[1..line.length].split(/:\s*/, 2)
					@vars[v] = k
					next
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
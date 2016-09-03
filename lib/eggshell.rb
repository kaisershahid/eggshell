# Eggshell.
module Eggshell
	# For complex nested content, use the block to execute content correctly.
	# Quick examples: nested loops, conditional statements.
	class Block
		def initialize(macro, handler, args, depth, delim = nil)
			@stack = [self]
			@lines = []
			@macro = macro
			@handler = handler
			@args = args
			@delim = delim

			# reverse, and swap out
			if @delim && @delim[0] == '{'
				@delim = @delim.reverse.gsub(/\{/, '}').gsub(/\[/, ']')
			else
				@delim = nil
			end

			@depth = depth
		end

		attr_reader :depth, :lines, :delim

		def cur
			@stack[-1]
		end

		def push(block)
			@stack[-1].lines << block
			@stack << block
		end

		def pop()
			@stack.pop
		end

		def collect(entry)
			@stack[-1].lines << entry
		end

		def process(buffer, depth = nil)
			@handler.process(buffer, @macro, @args, @lines, depth == nil ? @depth : depth)
		end

		def inspect
			"<BLOCK #{@macro} (#{@depth}) #{@handler.class} | #{@lines.inspect} >"
		end
	end

	class ProcessorContext
		# TBD
	end

	class Processor
		BLOCK_MATCH = /^([a-z0-9_-]+\.|[|\/#><*+-]+)/

		def initialize
			@vars = {:references => {}, :toc => [], :include_paths => [], 'log.level' => '1'}
			@funcs = {}
			@macros = {}
			@blocks = {}
			@expr_cache = {}

			@noop_macro = Eggshell::MacroHandler::Defaults::NoOpHandler.new
			@noop_block = Eggshell::BlockHandler::Defaults::NoOpHandler.new
		end

		def register_macro(handler, *macros)
			macros.each do |mac|
				@macros[mac] = handler
				_trace "register_macro: #{mac}: #{handler}"
			end
		end

		def register_block(handler, *blocks)
			blocks.each do |block|
				@blocks[block] = handler
				_trace "register_block: #{block}: #{handler}"
			end
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

		def expr_eval(struct)
			return Eggshell::ExpressionEvaluator.expr_eval(struct, @vars, @funcs)
		end

		# Expands expressions (`\${}`) and macro calls (`\@@macro\@@`).
		def expand_expr(expr)
			# replace dynamic placeholders
			# @todo expand to actual expressions
			buff = []
			esc = false
			exp = false
			mac = false

			toks = expr.split(/(\\|\$\{|\}|@@|"|')/)
			i = 0

			plain_str = ''
			expr_str = ''
			quote = nil
			expr_delim = nil

			while i < toks.length
				tok = toks[i]
				i += 1
				next if tok == ''

				if esc
					plain_str += tok
					esc = false
					next
				end

				if exp
					if quote
						expr_str += tok
						if tok == quote
							quote = nil
						end
					elsif tok == '"' || tok == "'"
						expr_str += tok
						quote = tok
					elsif tok == expr_delim
						struct = @expr_cache[expr_str]

						if !struct
							struct = Eggshell::ExpressionEvaluator.struct(expr_str)
							@expr_cache[expr_str] = struct
						end

						if !mac
							buff << expr_eval(struct)
						else
							args = struct[0]
							macro = args[1]
							args = args[2] || []
							macro_handler = @macros[macro]
							if macro_handler
								macro_handler.process(buff, macro, args, nil, -1)
							else
								_warn("macro (inline) not found: #{macro}")
							end
						end

						exp = false
						mac = false
						expr_delim = nil
						expr_str = ''
					else
						expr_str += tok
					end
				# only unescape if not in expression, since expression needs to be given as-is
				elsif tok == '\\'
					esc = true
					next
				elsif tok == '${' || tok == '@@'
					if plain_str != ''
						buff << plain_str
						plain_str = ''
					end
					exp = true
					expr_delim = '}'
					if tok == '@@'
						mac = true
						expr_delim = tok
					end
				else
					plain_str += tok
				end
			end

			# if exp -- throw exception?
			buff << plain_str if plain_str != ''
			return buff.join('')
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

			macro = nil
			macro_blocks = []
			macro_handler = nil
			macro_depth = call_depth + 1

			block = nil
			ext_line = nil

			block_handler = nil
			block_handler_raw = false

			i = 0

			while (i <= lines.length)
				line = nil
				indent_level = 0
				indents = ''

				# special condition to get a dangling line
				if i == lines.length
					if ext_line
						line = ext_line
						ext_line = nil
					else
						break
					end
				else
					line = lines[i]
				end
				i += 1

				if line.is_a?(Block)
					line.process(buff)
					next
				end

				orig = line
				oline = line

				# @todo configurable space tab?
				if line[0] == TAB || line[0..3] == TAB_SPACE
					tab = line[0] == TAB ? TAB : TAB_SPACE
					indent_level += 1
					offset = tab.length
					while line[offset...offset+tab.length] == tab
						indent_level += 1
						offset += tab.length
					end
					indents = line[0...offset]
					line = line[offset..-1]
				end

				line = line.rstrip
				line_end = ''
				if line.length < oline.length
					line_end = oline[line.length..-1]
				end

				# if line end in \, buffer and continue to next line;
				# join buffered line once \ no longer at end
				if line[-1] == '\\'
					if line[-2] != '\\'
						# special case: if a line consists of a single \, assume line ending is wanted,
						# otherwise join directly with previous line
						if line == '\\'
							line = line_end
						else
							line = line[0..-2]
						end

						if ext_line
							ext_line += indents + line
						else
							ext_line = indents + line
						end
						next
					else
						line = line[0..-2]
					end
				end

				# unescape escape
				line = line.gsub(/\\\\/, '\\')

				# join this line with last line and terminate last line
				if ext_line
					line = ext_line + line
					ext_line = nil
				end
				oline = line

				if line[0..1] == '!#'
					next
				end

				if block_handler_raw
					stat = block_handler.collect(line, buff, indents, indent_level)
					if stat != Eggshell::BlockHandler::COLLECT_RAW
						block_handler_raw = false
						if stat != Eggshell::BlockHandler::COLLECT
							block_handler = nil
							if stat == Eggshell::BlockHandler::RETRY
								i -= 1
							end
						end
					end
					next
				end

				# macro processing
				if line[0] == '@'
					macro = nil
					args = nil
					delim = nil

					if line.index(' ') || line.index('(') || line.index('{')
						# since the macro statement is essentially a function call, parse the line as an expression
						expr_struct = ExpressionEvaluator.struct(line)
						fn = expr_struct.shift
						if fn.is_a?(Array) && fn[0] == :fn
							macro = fn[1][1..fn[1].length]
							args = fn[2]
							if expr_struct[-1].is_a?(Array) && expr_struct[-1][0] == :brace_op
								delim = expr_struct[-1][1]
							end
						end
					else
						macro = line[1..line.length]
					end

					macro_handler = @macros[macro]
					if macro_handler
						if delim
							if block
								nblock = Block.new(macro, macro_handler, args, block.cur.depth + 1, delim)
								block.push(nblock)
							else
								block = Block.new(macro, macro_handler, args, macro_depth, delim)
							end
						else
							if block
								block.collect(Block.new(macro, macro_handler, args, macro_depth, nil))
							else
								macro_handler.process(buff, macro, args, nil, macro_depth)
							end
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
						block.cur.collect(oline)
					end
					next
				end

				if block_handler
					stat = block_handler.collect(line, buff, indents, indent_level)

					if stat == Eggshell::BlockHandler::COLLECT_RAW
						block_handler_raw = true
					elsif stat != Eggshell::BlockHandler::COLLECT
						block_handler = nil
						block_handler_raw = false
						if stat == Eggshell::BlockHandler::RETRY
							i -= 1
						end
					end
					line = nil
					next
				end

				# @todo try to map indent to a block handler
				next if line == ''

				# html block processing
				html = line.match(HTML_BLOCK)
				if html
					end_html = "</#{html[1]}>$"
					if !line.match(end_html)
						in_html = true
					end

					line = @vars['html.no_eval'] ? orig : expand_expr(orig)
					buff << line

					next
				elsif in_html
					line = @vars['html.no_eval'] ? orig : expand_expr(orig)
					buff << line
					if line.match(end_html)
						in_html = false
						end_html = nil
						@vars.delete('html.no_eval')
					end
					next
				end

				# check if the block starts off and matches against any handlers; if not, assign 'p' as default
				block_type = line.match(BLOCK_MATCH)
				if block_type && block_type[0].strip != ''
					block_type = block_type[1]
					block_type = block_type[0..-2] if block_type[-1] == '.'
				else
					block_type = 'p'
				end

				block_handler = @blocks[block_type]
				block_handler = @noop_block if !block_handler 
				stat = block_handler.start(block_type, line, buff, indents, indent_level)
				# block handler won't continue to next line; clear and possibly retry
				if stat != Eggshell::BlockHandler::COLLECT
					block_handler = nil
					if stat == Eggshell::BlockHandler::RETRY
						i -= 1
					end
				else
					line = nil
				end
			end

			if block_handler
				block_handler.collect(line, buff, indents, indent_level) if line
				block_handler.collect(nil, buff)
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
			'[-_' => '<u>',
			'_-]' => '</u>',
			'[-' => '<strike>',
			'-]' => '</strike>'
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

			macro = false
			macro_buff = ''

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
					buff << html_escape(expand_expr(part))
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
					part = part.gsub(/(\[\*{1,2}|\*{1,2}\]|\[_{1,2}|_{1,2}\]|\[-_?|_?-\])/, HASH_FMT_DECORATORS)

					# @todo add hooks for this so we don't have this overcomplicated code here
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

			return expand_expr(buff.join(''))
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

require_relative './eggshell/expression-evaluator.rb'
require_relative './eggshell/macro-handler.rb'
require_relative './eggshell/block-handler.rb'
require_relative './eggshell/bundles.rb'
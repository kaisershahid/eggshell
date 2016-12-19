# Eggshell.
module Eggshell

	# Tracks line and line count. Correctness depends
	class LineCounter
		def initialize(file = nil)
			@file = file
			@l_stack = []
			@l_count = []
			push
		end

		def line
			return @l_stack[-1]
		end
		
		def line_num
			c = 0
			@l_count.each do |lc|
				c += lc
			end
			return c
		end
		
		def file
			@file
		end

		# Sets the current line and offset. If offset is not nil, resets the counter to this value.
		# A sample situation where this is needed:
		#
		# pre.
		# block here
		# \
		# @macro {
		#     macro line 1
		#     macro line 2
		# }
		# \
		# last block
		# 
		# During execution, `@macro` would push a new count state. After execution is over, it's popped,
		# leaving the line number at the macro start. The main process loop, however, is keeping track
		# of all the lines during its own execution, so it can set the offset to the actual line again.
		def new_line(line, offset = nil)
			@l_stack[-1] = line
			@l_count[-1] = offset != nil ? offset : @l_count[-1] + 1
		end

		def push
			@l_stack << nil
			@l_count << 0
		end
		
		def pop
			@l_stack.pop
			@l_count.pop
			nil
		end
	end

	class Processor
		BLOCK_MATCH = /^([a-z0-9_-]+\.|[|\/#><*+-]+)/
		BLOCK_MATCH_PARAMS = /^([a-z0-9_-]+|[|\/#><*+-]+)\(/

		def initialize
			@context = Eggshell::ProcessorContext.new
			@vars = @context.vars
			@funcs = @context.funcs
			@macros = @context.macros
			@blocks = @context.blocks
			@block_params = @context.block_params
			@expr_cache = @context.expr_cache
			@ee = Eggshell::ExpressionEvaluator.new(@vars, @funcs)

			@noop_macro = Eggshell::MacroHandler::Defaults::NoOpHandler.new
			@noop_block = Eggshell::BlockHandler::Defaults::NoOpHandler.new
		end
		
		attr_reader :context

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
			@ee.register_functions(func_key, handler, func_names)
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

			toks = expr.gsub(/\\[trn]/, HASH_LINE_ESCAPE).split(/(\\|\$\{|\}|@@|"|')/)
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
		
		# html tags that have end-block checks. any block starting with one of these tags will have
		# its contents passed through until end of the tag
		# @todo what else should be treated?
		HTML_BLOCK = /^<(style|script|table|dl|select|textarea|\!--|\?)/
		HTML_BLOCK_END = {
			'<!--' => '-->',
			'<?' => '\\?>'
		}.freeze
		
		# For lines starting with only these tags, accept as-is
		HTML_PASSTHRU = /^\s*<(\/?(html|head|meta|link|title|body|br|section|div|blockquote|p|pre))/
		
		HASH_LINE_ESCAPE = {
			"\\n" => "\n",
			"\\r" => "\r",
			"\\t" => "\t",
			"\\\\" => "\\"
		}
		
		# @param Boolean is_default If true, associates these parameters with the 
		# `block_type` used in `get_block_param()` or explicitly in third parameter.
		# @param String block_type
		def set_block_params(params, is_default = false, block_type = nil)
			if block_type && is_default
				@block_params[block_type] = params
			else
				@block_params[:pending] = params
				@block_param_default = is_default
			end
		end
		
		# Gets the block parameters for a block type, and merges default values if available.
		def get_block_params(block_type)
			bp = @block_params.delete(:pending)
			if @block_params_default
				if block_type && bp
					@block_params[block_type] = bp if bp
				end
				@block_params_default = false
				bp = {} if !bp
			else
				bp = {} if !bp
				default = @block_params[block_type]
				if default
					default.each do |key,val|
						if !bp.has_key?(key) && val
							bp[key] = val.clone
						end
					end
				end
			end
			return bp
		end

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
			block_handler_indent = 0

			i = 0

			begin
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
					offset = 0
					tablen = 0
					if line[0] == TAB || line[0..3] == TAB_SPACE
						tab = line[0] == TAB ? TAB : TAB_SPACE
						tablen = tab.length
						indent_level += 1
						offset = tablen
						while line[offset...offset+tablen] == tab
							indent_level += 1
							offset += tablen
						end
						# if block_handler_indent > 0
						# 	indent_level -= block_handler_indent
						# 	offset -= (tablen * block_handler_indent)
						# end
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
					if line[-1] == '\\' && line.length > 1
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

					# join this line with last line and terminate last line
					if ext_line
						line = ext_line + line
						ext_line = nil
					end
					oline = line

					if line[0..1] == '!#'
						next
					end

					# relative indenting				
					if block_handler_indent > 0
						indents = indents[(tablen*block_handler_indent)..-1]
					end

					if block_handler_raw
						stat = block_handler.collect(line, buff, indents, indent_level - block_handler_indent)
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
						
						# special case: block parameter
						if macro == '!'
							set_block_params(args[0], args[1], args[2])
							next
						end

						macro_handler = @macros[macro]
						if macro_handler
							if delim
								if block
									nblock = Eggshell::Block.new(macro, macro_handler, args, block.cur.depth + 1, delim)
									block.push(nblock)
								else
									block = Eggshell::Block.new(macro, macro_handler, args, macro_depth, delim)
								end
							else
								if block
									block.collect(Eggshell::Block.new(macro, macro_handler, args, macro_depth, nil))
								else
									macro_handler.process(buff, macro, args, nil, macro_depth)
								end
							end
						else
							_warn("macro not found: #{macro} | #{line}")
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
							block.cur.collect(orig.rstrip)
						end
						next
					end

					if block_handler
						stat = block_handler.collect(line, buff, indents, indent_level - block_handler_indent)

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

					if line.match(HTML_PASSTHRU)
						if block_handler
							block_handler.collect(nil, buff)
							block_handler = nil
						end
						buff << fmt_line(line)
						next
					end

					# html block processing
					html = line.match(HTML_BLOCK)
					if html
						end_html = HTML_BLOCK_END["<#{html[1]}"]
						end_html = "</#{html[1]}>$" if !end_html
						if !line.match(end_html)
							in_html = true
						end

						line = @vars['html.no_eval'] ? orig : expand_expr(orig)
						buff << line.rstrip

						next
					elsif in_html
						if line == ''
							buff << line
						else
							line = @vars['html.no_eval'] ? orig : expand_expr(orig)
							buff << line.rstrip
						end

						if line.match(end_html)
							in_html = false
							end_html = nil
							@vars.delete('html.no_eval')
						end
						next
					end

					# @todo try to map indent to a block handler
					next if line == ''

					# check if the block starts off and matches against any handlers; if not, assign 'p' as default
					# two checks: `block(params).`; `block.`
					block_type = nil
					bt = line.match(BLOCK_MATCH_PARAMS)
					if bt
						idx0 = bt[0].length
						idx1 = line.index(').', idx0)
						if idx1
							block_type = line[0..idx0-2]
							params = line[0...idx1+1].strip
							line = line[idx1+2..line.length] || ''
							if params != ''
								struct = Eggshell::ExpressionEvaluator.struct(params)
								arg0 = struct[0][2][0]
								arg1 = struct[0][2][1]
								arg0 = expr_eval(arg0) if arg0
								set_block_params(arg0, arg1)
							end
						end
					else
						block_type = line.match(BLOCK_MATCH)
						if block_type && block_type[0].strip != ''
							block_type = block_type[1]
							len = block_type.length
							block_type = block_type[0..-2] if block_type[-1] == '.'
							line = line[len..line.length] || ''
						else
							block_type = nil
						end
					end


					block_type = 'p' if !block_type
					block_handler_indent = indent_level
					block_handler = @blocks[block_type]
					block_handler = @noop_block if !block_handler 
					stat = block_handler.start(block_type, line.lstrip, buff, indents, indent_level)
					# block handler won't continue to next line; clear and possibly retry
					if stat == Eggshell::BlockHandler::COLLECT_RAW
						block_handler_raw = true
					elsif stat != Eggshell::BlockHandler::COLLECT
						block_handler = nil
						if stat == Eggshell::BlockHandler::RETRY
							i -= 1
						end
					else
						line = nil
					end
				end

				if block_handler
					block_handler.collect(line, buff, indents, indent_level - block_handler_indent) if line
					block_handler.collect(nil, buff)
				end
			rescue => ex
				_error "Exception approximately on line: #{line}"
				_error ex.message + "\t#{ex.backtrace.join("\n\t")}"
				_error "vars = #{@vars.inspect}"
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

		# @todo more chars
		def html_escape(str)
			return str.gsub(/("|'|<|>|&)/, HASH_HTML_ESCAPE)
		end
		
		# Symbols in conjunction with '[' prefix and ']' suffix that define shortcut macros.
		# While extensible, the standard macros are: `*`, `**`, `_`, `__`, `-`, `-_`, `^`, `.`
		MACRO_OPS = "%~=!?.^\\/*_+-"
		INLINE_MARKUP_REGEX_OP = Regexp.new("\\[[#{MACRO_OPS}]+")
		INLINE_MARKUP = Regexp.new("(`|\\{\\{|\\}\\}|\\[[#{MACRO_OPS}]+|[#{MACRO_OPS}]+\\]|\\\\|\\|)")

		# Expands markup for a specific line.
		def fmt_line(expr)
			buff = []
			bt = false
			cd = false
			esc = false

			macro = false
			macro_buff = ''

			inline_op = nil
			inline_delim = nil
			inline_args = nil
			inline_part = nil
			inline_esc = false

			# split and preserve delimiters: ` {{ }} [[ ]]
			# - preserve contents of code blocks (only replacing unescaped placeholder values)
			## - handle anchor and image
			toks = expr.gsub(/\\[trn]/, HASH_LINE_ESCAPE).split(INLINE_MARKUP)
			i = 0

			while i < toks.length
				part = toks[i]
				i += 1
				next if part == ''

				if esc
					buff << '\\' if part == '\\' || part[0..1] == '${'
					buff << part
					esc = false
				elsif part == '\\'
					esc = true
				elsif part == '`' && !cd
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
				elsif (part[0] == '[' && part.match(INLINE_MARKUP_REGEX_OP))
					# parse OP + {term or '|'}* + DELIM
					inline_op = part
					i = expand_macro_brackets(inline_op, i, toks, buff)
					inline_op = nil
				else
				 	buff << part
				end
			end
			# if inline_op
			# 	inline_args << inline_part if inline_part
			# 	@macros[inline_op].process(buff, inline_op, inline_args, nil, nil)
			# end
			return expand_expr(buff.join(''))
		end
		
		def expand_macro_brackets(inline_op, i, toks, buff)
			inline_delim = inline_op.reverse.gsub('[', ']')
			inline_args = []
			inline_part = nil
			inline_esc = false

			# @todo check for quotes?
			# @todo make this a static function
			while i < toks.length
				part = toks[i]
				i += 1
				
				if inline_esc
					inline_part += part
					inline_esc = false if part != ''
				elsif part == '\\'
					esc = true
				elsif part.match(INLINE_MARKUP_REGEX_OP)
					i = expand_macro_brackets(part, i, toks, buff)
					inline_part = '' if !inline_part
					inline_part += buff.pop
				elsif part.end_with?(inline_delim) || part.end_with?('/]')
					# in the case where a special char immediately precedes end delimiter, move it on to
					# the inline body (e.g. `[//emphasis.//]` or `[*bold.*]`)
					len = part.end_with?(inline_delim) ? inline_delim.length : 2
					if part.length > len
						inline_part += part[0...-len]
					end
					break
				elsif part == '|'
					inline_args << inline_part
					inline_part = nil
				else
					inline_part = '' if !inline_part
					inline_part += part
				end
			end

			inline_args << inline_part if inline_part
			if @macros[inline_op]
				@macros[inline_op].process(buff, inline_op, inline_args, nil, nil)
			else
				buff << "#{inline_op}#{inline_args.join('|')}#{inline_delim}"
			end

			return i
		end
	end
end

require_relative './eggshell/block.rb'
require_relative './eggshell/processor-context.rb'
require_relative './eggshell/expression-evaluator.rb'
require_relative './eggshell/macro-handler.rb'
require_relative './eggshell/block-handler.rb'
require_relative './eggshell/bundles.rb'
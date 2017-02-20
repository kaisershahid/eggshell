module Eggshell
	class Processor
		BLOCK_MATCH = /^([a-z0-9_-]+\.)/
		BLOCK_MATCH_PARAMS = /^([a-z0-9_-]+)\(/

		def initialize
			@context = Eggshell::ProcessorContext.new
			@vars = @context.vars
			@funcs = @context.funcs
			@macros = @context.macros
			@blocks = @context.blocks
			@blocks_map = @context.blocks_map
			@block_params = @context.block_params
			@expr_cache = @context.expr_cache
			@fmt_handlers = @context.fmt_handlers
			@ee = Eggshell::ExpressionEvaluator.new(@vars, @funcs)

			@noop_macro = Eggshell::MacroHandler::Defaults::NoOpHandler.new
			@noop_block = Eggshell::BlockHandler::Defaults::NoOpHandler.new
		end
		
		attr_reader :context

		def add_block_handler(handler, *names)
			_trace "add_block_handler: #{names.inspect} -> #{handler.class}"
			@blocks << handler
			names.each do |name|
				@blocks_map[name] = handler
			end
		end
		
		def rem_block_handler(*names)
			_trace "rem_block_handler: #{names.inspect}"
			names.each do |name|
				handler = @blocks_map.delete(name)
				@blocks.delete(handler)
			end
		end
		
		def add_macro_handler(handler, *names)
			_trace "add_macro_handler: #{names.inspect} -> #{handler.class}"
			names.each do |name|
				@macros[name] = handler
			end
		end
		
		def rem_macro_handler(*names)
			_trace "rem_macro_handler: #{names.inspect}"
			names.each do |name|
				@macros.delete(name)
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
			return if @vars['log.level'] < 1
			$stderr.write("[INFO]  #{msg}\n")
		end

		def _debug(msg)
			return if @vars['log.level'] < 2
			$stderr.write("[DEBUG] #{msg}\n")
		end

		def _trace(msg)
			return if @vars['log.level'] < 3
			$stderr.write("[TRACE] #{msg}\n")
		end

		attr_reader :vars

		def expr_eval(struct)
			return Eggshell::ExpressionEvaluator.expr_eval(struct, @vars, @funcs)
		end

		# Expands expressions (`\${}`) and macro calls (`\@@macro\@@`).
		# @todo deprecate @@macro@@?
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
					plain_str += '\\' + tok
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

		# Sets the default output object. Must support {{<<}} and {{join(String)}}.
		#
		# If {{out}} is a `Class`, must support empty initialization.
		def set_out(out)
			@out = out
		end

		def get_out
			if !@out
				[]
			elsif @out.is_a?(Class)
				@out.new
			else
				@out
			end
		end

		BH = Eggshell::BlockHandler
		
		COMMENT = '#!'
		DIRECTIVE = '#>'

		def preprocess(lines, line_count = 0)
			line_start = line_count
			line_buff = nil
			indent = 0
			mode = nil
			
			in_html = false
			end_html = nil
			
			parse_tree = Eggshell::ParseTree.new

			"""
			algorithm for normalizing lines:
			
			- skip comments (process directive if present)
			- if line is continuation, set current line = last + current
			- if line ends in \ and is not blank otherwise, set new continuation and move to next line
			- if line ends in \ and is effectively blank, append '\n'
			- calculate indent level
			"""
			i = 0
			begin
				while i < lines.length
					oline = lines[i]
					i += 1

					line_count += 1

					hdr = oline.lstrip[0..1]
					if hdr == COMMENT
						next
					end

					line = oline.chomp
					line_end = oline[line.length..-1]
					if line_buff
						line_buff += line
						line = line_buff
						line_buff = nil
					else
						line_start += 1
					end
					
					_hard_return = false

					# if line ends in a single \, either insert hard return into current block (with \n)
					# or init line_buff to collect next line
					if line[-1] == '\\'
						if line[-2] != '\\'
							nline = line[0...-1]
							# check if line is effectively blank, but add leading whitespace back
							# to maintain tab processing
							if nline.strip == ''
								line = "#{nline}\n"
								line_end = ''
								_hard_return = true
							else
								line_buff = nline
								next
							end
						end
					end

					# detect tabs (must be consistent per-line)
					_ind = 0
					tab_str = line[0] == TAB ? TAB : nil
					tab_str = line.index(TAB_SPACE) == 0 ? TAB_SPACE : nil if !tab_str
					indent_str = ''
					if tab_str
						_ind += 1
						_len = tab_str.length
						_pos = _len
						while line.index(tab_str, _pos)
							_pos += _len
							_ind += 1
						end
						line = line[_pos..-1]

						# trim indent chars based on block_handler_indent
						if indent > 0
							_ind -= indent
							_ind = 0 if _ind < 0
						end
					end
					
					line_norm = Line.new(line, tab_str, _ind, line_start, oline.chomp)
					line_start = line_count

					if parse_tree.mode == :raw
						stat = parse_tree.collect(line_norm)
						next if stat != BH::RETRY
						parse_tree.push_block
					end

					# macro processing
					if line[0] == '@'
						parse_tree.new_macro(line_norm, line_count)
						next
					elsif parse_tree.macro_delim_match(line_norm, line_count)
						next
					end

					if parse_tree.mode == :block
						stat = parse_tree.collect(line_norm)
						if stat == BH::RETRY
							parse_tree.push_block
						else
							next
						end
					end

					# blank line and not in block
					if line == ''
						parse_tree.push_block
						next
					end

					found = false
					@blocks.each do |handler|
						stat = handler.can_handle(line)
						next if stat == BH::RETRY
						
						parse_tree.new_block(handler, handler.current_type, line_norm, stat, line_count)
						found = true
						_trace "(#{handler.current_type}->#{handler}) #{line} -> #{stat}"
						break
					end

					if !found
						@blocks_map['p'].can_handle('p.')
						parse_tree.new_block(@blocks_map['p'], 'p', line_norm, BH::COLLECT, line_count)
					end
				end
				parse_tree.push_block
				# @todo check if macros left open
			rescue => ex
				_error "Exception approximately on line: #{line}"
				_error ex.message + "\t#{ex.backtrace.join("\n\t")}"
				#_error "vars = #{@vars.inspect}"
			end
			
			parse_tree
		end
		
		# This string in a block indicates that a piped macro's output should be inserted at this location
		# rather than immediately after last line. For now, this is only checked for on the last line. 
		# 
		# Multiple inline pipes can be specified on this line, with each pipe corresponding to each macro
		# chained to the block. Any unfilled pipe will be replaced with a blank string.
		#
		# To escape the pipe, use a backslash anywhere [*AFTER*] the initial dash (e.g. `-\\>*<-`).
		PIPE_INLINE = '->*<-'

		# Goes through each item in parse tree, collecting output in the following manner:
		#
		# # {{String}}s and {{Line}}s are outputted as-is
		# # macros and blocks with matching handlers get {{process}} called
		#
		# All output is joined with `\\n` by default.
		#
		# The output object and join string can be overridden through the {{opts}} parameter
		# keys {{:out}} and {{:joiner}}.
		#3
		# @param Eggshell::ParseTree,Array parse_tree Parsed document.
		# @param Integer call_depth
		# @param Hash opts
		def assemble(parse_tree, call_depth = 0, opts = {})
			opts = {} if !opts.is_a?(Hash)
			out = opts[:out] || get_out
			joiner = opts[:join] || "\n"

			parse_tree = parse_tree.tree if parse_tree.is_a?(Eggshell::ParseTree)
			raise Exception.new("input not an array or ParseTree (depth=#{call_depth}") if !parse_tree.is_a?(Array)
			# @todo defer process to next unit so macro can inject lines back into previous block
			
			last_type = nil
			last_line = 0
			deferred = nil

			parse_tree.each do |unit|
				if unit.is_a?(String)
					out << unit
					last_line += 1
					last_type = nil
				elsif unit.is_a?(Eggshell::Line)
					out << unit.to_s
					last_line = unit.line_nameum
					last_type = nil
				elsif unit.is_a?(Array)
					handler = unit[0] == :block ? @blocks_map[unit[1]] : @macros[unit[1]]
					name = unit[1]

					if !handler
						_warn "handler not found: #{unit[0]} -> #{unit[1]}"
						next
					end

					args_o = unit[2] || []
					args = []
					args_o.each do |arg|
						args << expr_eval(arg)
					end
						
					lines = unit[ParseTree::IDX_LINES]
					lines_start = unit[ParseTree::IDX_LINES_START]
					lines_end = unit[ParseTree::IDX_LINES_END]

					_handler, _name, _args, _lines = deferred

					if unit[0] == :block
						if deferred
							# two cases:
							# 1. this block is immediately tied to block-macro chain and is continuation of same type of block
							# 2. part of block-macro chain but not same type, or immediately follows another block
							if last_type == :macro && (lines_start - last_line <= 1) && _handler.equal?(handler, name)
								lines.each do |line|
									_lines << line
								end
							else
								_handler.process(_name, _args, _lines, out, call_depth)
								deferred = [handler, name, args, lines.clone]
							end
						else
							deferred = [handler, name, args, lines.clone]
						end

						last_line = lines_end
					else
						# macro immediately after a block, so assume that output gets piped into last lines
						# of closest block
						if deferred && lines_start - last_line == 1
							_last = _lines[-1]
							pinline = false
							pipe = _lines
							if _last.to_s.index(PIPE_INLINE)
								pipe = []
								pinline = true
							end

							handler.process(name, args, lines, pipe, call_depth)

							# inline pipe; join output with literal \n to avoid processing lines in block process
							if pinline
								if _last.is_a?(Eggshell::Line)
									_lines[-1] = _last.replace(_last.line.sub(PIPE_INLINE, pipe.join('\n')))
								else
									_lines[-1] = _last.sub(PIPE_INLINE, pipe.join('\n'))
								end
							end
						else
							if deferred
								_handler.process(_name, _args, _lines, out, call_depth)
								deferred = nil
							end
							handler.process(name, args, lines, out, call_depth)
						end
						last_line = lines_end
					end

					last_type = unit[0]
				elsif unit
					_warn "not sure how to handle #{unit.class}"
					_debug unit.inspect
					last_type = nil
				end
			end

			if deferred
				_handler, _name, _args, _lines = deferred
				_handler.process(_name, _args, _lines, out, call_depth)
				deferred = nil
			end
			out.join(joiner)
		end

		def process(lines, line_count = 0, call_depth = 0)
			parse_tree = preprocess(lines, line_count)
			assemble(parse_tree.tree, call_depth)
		end

		# Register inline format handlers with opening and closing tags.
		# Typically, tags can be arbitrarily nested. However, nesting can be
		# shut off completely or selectively by specifying 0 or more tags
		# separated by a space (empty string is completely disabled).
		# 
		# @param Array tags Each entry should be a 2- or 3-element array in the
		# following form: {{[open, close[, non_nest]]}}
		# @todo if opening tag is regex, don't escape (but make sure it doesn't contain {{^}} or {{$}})
		def add_format_handler(handler, tags)
			return if !tags.is_a?(Array)
			
			tags.each do |entry|
				open, close, no_nest = entry
				no_nest = '' if no_nest.is_a?(TrueClass)
				@fmt_handlers[open] = [handler, close, no_nest]
				_trace "add_format_handler: #{open} #{close} (non-nested: #{no_nest.inspect})"
			end

			# regenerate splitting pattern going from longest to shortest
			openers = @fmt_handlers.keys.sort do |a, b|
				b.length <=> a.length
			end

			regex = ''
			openers.each do |op|
				regex = "#{regex}|#{Regexp.quote(op)}|#{Regexp.quote(@fmt_handlers[op][1])}"
			end

			@fmt_regex = /(\\|'|"#{regex})/
		end

		# Expands inline formatting with {{Eggshell::FormatHandler}}s.
		def expand_formatting(str)
			toks = str.gsub(PIPE_INLINE, '').split(@fmt_regex)
			toks.delete('')

			buff = ['']
			quote = nil
			opened = []
			closing = []
			non_nesting = []

			i = 0
			while i < toks.length
				tok = toks[i]
				i += 1
				if tok == '\\'
					# preserve escape char otherwise we lose things like \n or \t
					buff[-1] += tok + toks[i]
					i += 1
				elsif quote
					quote = nil if tok == quote
					buff[-1] += tok
				elsif tok == '"' || tok == "'"
					# only open quote if there's whitespace or blank string preceeding it
					quote = tok if opened[-1] && (!buff[-1] || buff[-1] == '' || buff[-1].match(/\s$/))
					buff[-1] += tok
				elsif @fmt_handlers[tok] && (!non_nesting[-1] || non_nesting.index(tok))
					handler, closer, non_nest = @fmt_handlers[tok]
					opened << tok
					closing << closer
					non_nesting << non_nest
					buff << ''
				elsif tok == closing[-1]
					opener = opened.pop
					handler = @fmt_handlers[opener][0]
					closing.pop
					non_nesting.pop

					# @todo insert placeholder and swap out at end? might be a prob if value has to be escaped
					bstr = buff.pop
					buff[-1] += handler.format(opener, bstr)
				else
					buff[-1] += tok
				end
			end

			opened.each do |op|
				bstr = buff.pop
				buff[-1] += op + bstr
				_warn "expand_formatting: unclosed #{op}, not doing anything: #{bstr}"
				#_warn toks.inspect
			end

			buff.join('')
		end

		def self.parse_block_start(line)
			block_type = nil
			args = []

			bt = line.match(BLOCK_MATCH_PARAMS)
			if bt
				idx0 = bt[0].length
				idx1 = line.index(').', idx0)
				if idx1
					block_type = line[0..idx0-2]
					params = line[0...idx1+1].strip
					line = line[idx1+2..line.length] || ''
					if params != ''
						struct = ExpressionEvaluator.struct(params)
						args = struct[0][2]
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
			
			[block_type, args, line]
		end

		def self.parse_macro_start(line)
			macro = nil
			args = []
			delim = nil

			# either macro is a plain '@macro' or it has parameters/opening brace
			if line.index(' ') || line.index('(') || line.index('{')
				# since the macro statement is essentially a function call, parse the line as an expression to get components
				expr_struct = ExpressionEvaluator.struct(line)
				fn = expr_struct.shift
				if fn.is_a?(Array) && (fn[0] == :fn || fn[0] == :var)
					macro = fn[1][1..fn[1].length]
					args = fn[2]
					if expr_struct[-1].is_a?(Array) && expr_struct[-1][0] == :brace_op
						delim = expr_struct[-1][1]
					end
				end
			else
				macro = line[1..line.length]
			end
			
			[macro, args, delim]
		end

		BACKSLASH_REGEX = /\\(u[0-9a-f]{4}|u\{[^}]+\}|.)/i
		BACKSLASH_UNESCAPE_MAP = {
			'f' => "\f",
			'n' => "\n",
			'r' => "\r",
			't' => "\t",
			'v' => "\v"
		}.freeze

		# Unescapes backslashes and Unicode characters.
		# 
		# If a match is made against {{BACKSLASH_UNESCAPE_MAP}} that character will 
		# be used, otherwise, the literal is used.
		#
		# Unicode sequences are standard Ruby-like syntax: {{\uabcd}} or {{\u{seq1 seq2 ...}}}.
		def self.unescape(str)
			str = str.gsub(BACKSLASH_REGEX) do |match|
				if match.length == 2
					c = match[1]
					BACKSLASH_UNESCAPE_MAP[c] || c
				else
					if match[2] == '{'
						parts = match[3..-1].split(' ')
						buff = ''
						parts.each do |part|
							buff += [part.to_i(16)].pack('U')
						end
						buff
					else
						[match[2..-1].to_i(16)].pack('U')
					end
				end
			end
		end

		def unescape(str)
			return self.class.unescape(str)
		end
		
		# Calls inline formatting, expression extrapolator, and backslash unescape.
		def expand_all(str)
			unescape(expand_expr(expand_formatting(str)))
		end
	end
end
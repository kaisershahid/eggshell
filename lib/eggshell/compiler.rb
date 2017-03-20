# Interfaces and methods to convert a parsed Eggshell document into a class for reuse
# as a template.
#
# The reference implementation, {@see DefaultAssembler} generates high-level code as follows:
# 
# pre.
# main_function(args*)
# 	call_block_handler*
# 	call_macro_method*
# macro_method(out, call_depth)
# 	call_macro_handler
# macro_method_expanded(out, call_depth)
# 	native_expansion_of_macro*
module Eggshell; module Compiler
	module Assembler
		# Sets assembler-specific options. This should initialize the main method
		# via {@see add_func()}.
		# @param Eggshell::Processor A reference processor instance to validate certain conditions
		# (e.g. what to do in a block-macro-block chain).
		def init(processor, opts = {})
		end

		# Iterates over parse tree to generate compiler events.
		def assemble(parse_tree)
		end

		# Generates a new function that statements will be inserted into.
		def add_func(name)
		end
		
		# Pops the current function off stack, sending statements to the main function.
		def pop_func
		end
		
		# Inserts a raw line into output.
		def do_line(line)
		end
		
		# Initializes handler and lines for a block.
		def start_block(name, args, lines)
		end
		
		# Initializes handler and lines for a macro.
		def start_macro(name, args, lines)
		end
		
		# Inject lines into current handler. If a line is either a block or macro, call 
		# {@see assemble()} on it.
		def add_lines(lines)
		end
		
		# Inserts lines from an equivalent
		def chain_append(lines)
		end
		
		# Inserts statements to prepare for inlined macro output.
		def pipe_inline_start
		end
		
		# Inserts statements to inject inlined macro output into previous block.
		def pipe_inline_end
		end
		
		# Inserts statements to append macro output into previous block.
		def pipe_append_start
		end
		
		def pipe_append_end
		end

		def commit_handler(name, args)
			@pending_funcs[-1][1] << insert_statement(HANDLER_COMMIT, 'HANDLER_NAME' => name, 'ARGS' => args.inspect)
		end

		def write(stream)
		end
		
		# Iterates over each line/block/macro in the parsed document and generates events. This should
		# also take care of detecting block-macro chains (appending and inlining macros).
		def assemble(parse_tree)
		end
	end

	class DefaultAssembler
		include Assembler

		# :func_main: entry point to processing data
		# :func_main_body: starting body initialization
		# @todo :exception_handler: defaults to 'raise Exception.new'
		# @todo :
		def init(processor, opts = {})
			@processor = processor
			@opts = opts
			@pending_funcs = []
			@funcs = []
			@macro_counter = 1
			@handler_stack = []
			@call_depth = 0
			@chained_macros = []
			add_func(opts[:func_main] ? opts[:func_main] : 'process()', opts[:func_main_body] ? opts[:func_main_body] : BODY)
		end

		def add_func(name, func_body)
			@pending_funcs << [name, [func_body]]
		end
		
		def pop_func
			@funcs << @pending_funcs.pop
		end
		
		def do_line(line)
			@pending_funcs[-1][1] << insert_statement(LINE_OUT, 'LINE' => line.inspect)
		end
		
		def start_block(name, args, lines)
			#puts "> b: #{name}"
			@handler_stack << :block
			@pending_funcs[-1][1] << insert_statement(BLOCK_HANDLER, 'HANDLER_NAME' => name, 'ARGS' => args.inspect, 'RAW_LINES' => lines.inspect)
		end
		
		def start_macro(name, args, lines)
			#puts "> m: #{name}"
			name_esc = name.gsub(/[^\w]+/, '_')
			func_name = "__macro_#{name_esc}_#{@macro_counter}"
			@pending_funcs[-1][1] << "\t#{func_name}(out, call_depth + 1)"

			add_func("#{func_name}(out, call_depth)", BODY_MACRO)
			@macro_counter += 1
			@handler_stack << :macro
			@call_depth += 1

			# @todo handle for/while/loop as well
			if name == 'pipe' && args && args[0].is_a?(Hash) && args[0]['chained'] == 'if'
				@pending_funcs[-1][1] << "\t# chained macros: #{args[0]['chained']}"
				@chained_macros << {:type=>args[0]['chained'], :args=>args}
			end
			
			@pending_funcs[-1][1] << insert_statement(MACRO_HANDLER, 'HANDLER_NAME' => name, 'ARGS' => args.inspect, 'RAW_LINES' => lines.inspect)
		end

		# takes chained if-elsif-else macros and creates actual if/elsif/else code
		# @param Array args Arguments given to @pipe chain
		def _expand_if(args, lines)
			id = Time.new.to_i.to_s
			@pending_funcs[-1][1] << insert_statement(HANDLER_SAVE_REF, 'ID' => id)
			lines.each do |line|
				type = line[1]
				cond_args = line[2]
				cond = cond_args.is_a?(Array) ? cond_args[0] : nil
				# @todo expand condition check as natively as possible
				if type != 'else'
					@pending_funcs[-1][1] << "\t#{type} (processor.expr_eval(#{cond.inspect}))"
				else
					@pending_funcs[-1][1] << "\telse"
				end

				#puts ">> #{line[3][0..2].inspect}"
				assemble(line[3])

				if type == 'else'
					@pending_funcs[-1][1] << "\tend"
				end
			end
			@pending_funcs[-1][1] << insert_statement(HANDLER_RESTORE_REF, 'ID' => id)
		end
		
		def _expand_for(args, lines)
		end
		
		def _expand_while(args, lines)
		end
		
		def add_lines(lines)
			if @chained_macros.length > 0
				info = @chained_macros.pop
				_expand_if(info[:args], lines)
			else
				lines.each do |line|
					if line.is_a?(String)
						@pending_funcs[-1][1] << insert_statement(LINE, 'LINE' => line.inspect)
					elsif line.is_a?(Eggshell::Line)
						@pending_funcs[-1][1] << insert_statement(LINE_EGG, 'LINE' => line.line.inspect, 'TAB' => line.tab_str.inspect, 'INDENT' => line.indent_lvl, 'LINE_NUM' => line.line_num)
					elsif line.is_a?(Array)
						id = Time.new.to_i.to_s
						@pending_funcs[-1][1] << insert_statement(HANDLER_SAVE_REF, 'ID' => id)
						assemble([line])
						@pending_funcs[-1][1] << insert_statement(HANDLER_RESTORE_REF, 'ID' => id)
					end
				end
			end
		end
		
		def chain_append(lines)
			add_lines(lines)
		end
		
		def pipe_inline_start
			@pending_funcs[-1][1] << PIPE_INLINE_START
		end
		
		def pipe_inline_end
			@pending_funcs[-1][1] << PIPE_INLINE_END
		end
		
		def pipe_append_start
			@pending_funcs[-1][1] << PIPE_APPEND_START
		end
		
		def pipe_append_end
			@pending_funcs[-1][1] << PIPE_APPEND_END
		end
		
		def commit_handler(name, args)
			type = @handler_stack.pop
			@pending_funcs[-1][1] << insert_statement(HANDLER_COMMIT, 'HANDLER_NAME' => name, 'ARGS' => args.inspect)
			@pending_funcs[-1][1] << "# COMMIT #{name} (#{type})\n"
			if type == :macro
				pop_func()
				@call_depth -= 1
			end
		end

		def insert_statement(str, kv)
			kv.each do |key, val|
				str = str.gsub("@@#{key}@@", val.to_s)
			end
			
			str
		end

		def assemble(parse_tree)
			joiner = @opts[:join] || "\n"

			parse_tree = parse_tree.tree if parse_tree.is_a?(Eggshell::ParseTree)
			raise Exception.new("input not an array or ParseTree") if !parse_tree.is_a?(Array)
			
			last_type = nil
			last_line = 0
			deferred = nil
			inline_count = -1

			parse_tree.each do |unit|
				if unit.is_a?(String)
					do_line(unit)
					last_line += 1
					last_type = nil
				elsif unit.is_a?(Eggshell::Line)
					do_line(unit.to_s)
					last_line = unit.line_nameum
					last_type = nil
				elsif unit.is_a?(Array)
					name = unit[1]

					args_o = unit[2] || []
					args = args_o
						
					lines = unit[ParseTree::IDX_LINES]
					lines_start = unit[ParseTree::IDX_LINES_START]
					lines_end = unit[ParseTree::IDX_LINES_END]

					_handler, _name, _args, _lines = deferred

					if unit[0] == :block
						handler = @processor.get_block_handler(name)
						if deferred
							if last_type == :macro && (lines_start - last_line <= 1) && _handler.equal?(handler, name)
								chain_append([])
								add_lines(lines)
							else
								inline_count = -1
								commit_handler(_name, args_o)
								#@pending_funcs[-1][1] << "# block: #{name} (LINE: #{lines_start})"
								start_block(name, args_o, [])
								add_lines(lines)
								deferred = [handler, name, args, lines]
							end
						else
							#@pending_funcs[-1][1] << "# block: #{name} (LINE: #{lines_start})"
							inline_count = -1
							start_block(name, args_o, [])
							add_lines(lines)
							deferred = [handler, name, args, lines]
						end

						last_line = lines_end
					else
						handler = @processor.get_macro_handler(name)
						@pending_funcs[-1][1] << "\t# macro: #{name} (LINE: #{lines_start})"
						if deferred && lines_start - last_line == 1
							_last = _lines[-1]
							pinline = false

							# check last line of last block for number of inlines
							if inline_count == -1
								inline_count = 0
								_last.to_s.gsub(Eggshell::Processor::PIPE_INLINE) do |m|
									inline_count += 1
								end
								inline_count = -1 if inline_count == 0
							end

							if inline_count > 0
								pinline = true
								inline_count -= 1
								pipe_inline_start()
							else
								pipe_append_start()
							end

							start_macro(name, args_o, [])
							add_lines(lines)
							commit_handler(name, args_o)

							# inline pipe; join output with literal \n to avoid processing lines in block process
							if pinline
								pipe_inline_end()
							else
								pipe_append_end()
							end
						else
							if deferred
								#start_block(_name, _args, [])
								#add_lines(_lines)
								commit_handler(_name, _args)
								deferred = nil
							end

							start_macro(name, args_o, [])
							add_lines(lines)
							commit_handler(name, args_o)
						end
						last_line = lines_end
					end

					last_type = unit[0]
				elsif unit
					$stderr.write "not sure how to handle #{unit.class}\n"
					$stderr.write unit.inspect
					$stderr.write "\n"
					last_type = nil
				end
			end

			if deferred
				_handler, _name, _args, _lines = deferred
				commit_handler(_name, _args)
				deferred = nil
			end
		end

		def write(stream)
			while @pending_funcs.length > 0
				pop_func()
			end
			
			@funcs.reverse.each do |func_entry|
				stream.write("def #{func_entry[0]}\n")
				stream.write(func_entry[1].join("\n"))
				stream.write("end\n\n")
			end
		end
	end

	BODY = <<-DOC
	processor = @eggshell
	out = @out
	call_depth = 0
DOC

	BODY_MACRO = <<-DOC
	processor = @eggshell
DOC

	LINE_OUT = <<-DOC
	out << @@LINE@@
DOC

	LINE = <<-DOC
	lines << @@LINE@@
DOC

	LINE_EGG = <<-DOC
	lines << Eggshell::Line.new(@@LINE@@, @@TAB@@, @@INDENT@@, @@LINE_NUM@@)
DOC

	BLOCK_HANDLER = <<-DOC
	handler = processor.get_block_handler('@@HANDLER_NAME@@')
	lines = @@RAW_LINES@@
DOC

	HANDLER_COMMIT = <<-DOC
	handler.process('@@HANDLER_NAME@@', @@ARGS@@, lines, out, call_depth)
DOC

	MACRO_HANDLER = <<-DOC
	handler = processor.get_macro_handler('@@HANDLER_NAME@@')
	lines = @@RAW_LINES@@
DOC

	PIPE_APPEND_START = <<-DOC
	# pipe:append
	_handler = handler
	_out = out
	out = lines
DOC

	PIPE_APPEND_END = <<-DOC
	lines = out
	out = _out
	handler = _handler
	_out = nil
	_handler = nil
	# pipe:append:end
DOC

	PIPE_INLINE_START = <<-DOC
	# pipe:inline
	_lines = lines
	_out = out
	out = []
DOC

	HANDLER_SAVE_REF = <<-DOC
	handler_@@ID@@ = handler
	lines_@@ID@@ = lines
DOC

	HANDLER_RESTORE_REF = <<-DOC
	handler = handler_@@ID@@
	lines = lines_@@ID@@
DOC

	PIPE_INLINE_END = <<-DOC
	if _lines[-1].is_a?(Eggshell::Line)
		_lines[-1] = lines[-1].replace(_lines[-1].line.sub(Eggshell::Processor::PIPE_INLINE, out.join('\\n')))
	else
		_lines[-1] = _lines[-1].sub(Eggshell::Processor::PIPE_INLINE, out.join('\\n'))
	end

	lines = _lines
	out = _out
	_out = nil
	_lines = nil
	# pipe:inline:end
DOC

	# When a block immediately follows in a block-macro chain and this block is same as initial block
	BLOCK_CHAIN_APPEND = <<-DOC
	lines += @@RAW_LINES@@
DOC

end; end
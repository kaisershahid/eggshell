class Eggshell::Bundles::Basics
	BUNDLE_ID = 'basics'

	def self.new_instance(proc, opts = nil)
		BasicBlocks.new.set_processor(proc)
		InlineMacros.new.set_processor(proc)
		BasicMacros.new.set_processor(proc)
		ControlMacros.new.set_processor(proc)

		proc.register_functions('', StdFunctions::FUNC_NAMES)
		proc.register_functions('sprintf', Kernel)
	end

	# `table` block parameters:
	# - `row.classes`: defaults to `['odd', 'even']`. The number of elements represents the number of cycles.
	class BasicBlocks
		include Eggshell::BlockHandler

		CELL_ATTR_START = '!'
		CELL_ATTR_END = '<!'

		def set_processor(proc)
			@proc = proc
			@proc.register_block(self, *%w(h1 h2 h3 h4 h5 h6 hr table pre p bq div raw # - / | >))
			@header_list = []
		end

		def start(name, line, buffer, indents = '', indent_level = 0)
			set_block_params(name)
			bp = @block_params[name]

			# @todo read block_param arguments
			if name[0] == 'h'
				if name == 'hr'
					buffer << "<hr />"
				else
					lvl = name[1].to_i
					clazz = bp['class'] || ''
					style = bp['style'] || '' 
					attrs = bp['attributes'] || []
					abuff = []
					attrs.each do |key,val|
						abuff << "#{key}='#{val}'"
					end
					# @todo track id and header type for TOC
					id = bp['id'] || line.downcase.strip.gsub(/[^a-z0-9_-]+/, '-')
					title = @proc.fmt_line(line)
					buffer << "<#{name} id='#{id}' class='#{clazz}' style='#{style}' #{abuff.join(' ')}>#{title}</#{name}>"
					@header_list << {:level => lvl, :id => id, :title => title}
				end
				return DONE
			end

			if name == '#' || name == '-'
				@type = :list
				@lines = [[line, indent_level]]
				return COLLECT
			end

			if name == 'table' || name == '/' || name == '|'
				@type = :table
				@lines = []
				@lines << line if name != 'table'
				return COLLECT
			end

			if name == '>'
				@type = :dt
				@lines = [line.split('::', 2)]
				return COLLECT
			end

			# assume block text
			@type = name
			if line.index(name) == 0
				line = line.lstrip
			end
			@lines = [@type == 'raw' ? line : @proc.fmt_line(line)]

			return COLLECT
		end

		def collect(line, buff, indents = '', indent_level = 0)
			line = '' if !line
			ret = COLLECT
			if @type == :list
				ret = do_list(line, buff, indents, indent_level)
			elsif @type == :table
				ret = do_table(line, buff, indents, indent_level)
			elsif @type == :dt
				ret = do_dt(line, buff, indents, indent_level)
			else
				ret = do_default(line, buff, indents, indent_level)
			end
			return ret
		end

		def do_list(line, buff, indents = '', indent_level = 0)
			ret = COLLECT
			if line && (line[0] == '#' || line[0] == '-')
				@lines << [line, indent_level]
			else
				# if non-empty line, reprocess this line but process buffer
				ret = (line && line != '') ? RETRY : DONE
				order_stack = []
				otype_stack = []
				last = nil
				@lines.each do |pair|
					line = pair[0]
					indent = pair[1]
					type = line[0] == '-' ? 'ul' : 'ol'
					if order_stack.length == 0
						order_stack << "<#{type}>"
						otype_stack << type
					# @todo make sure that previous item was a list
					# remove closing li to enclose sublist
					elsif indent > (otype_stack.length-1) && order_stack.length > 0
						last = order_stack[-1]
						last = last[0...last.length-5]
						order_stack[-1] = last

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
					order_stack << "#{"\t"*indent}<li>#{@proc.fmt_line(line[1...line.length].strip)}</li>"
				end

				# close nested lists
				d = otype_stack.length
				c = 1
				otype_stack.each do |type|
					ident = d - c
					order_stack << "#{"\t" * ident}</#{type}>#{c == d ? '' : "</li>"}"
					c += 1
				end
				buff << order_stack.join("\n")
			end
			ret
		end

		def do_table(line, buff, indents = '', indent_level = 0)
			ret = COLLECT
			if line[0] == '|' || line[0] == '/'
				@lines << line
			else
				ret = (line[0] != '\\' && line != '') ? RETRY : DONE
				map = @block_params['table']
				tbl_class = map['class'] || ''
				tbl_style = map['style'] || ''
				tbl_attrib = ''
				if map['attribs'].is_a?(String)
					tbl_attrib = map['attribs']
				elsif map['attribs'].is_a?(Hash)
					map['attribs'].each do |key,val|
						tbl_attrib = "#{tbl_attrib} #{key}='#{val}'"
					end
				end
				row_classes = map['row.classes']
				row_classes = ['odd', 'even'] if !row_classes.is_a?(Array)

				@proc.vars['t.row'] = 0
				buff << "<table class='#{tbl_class}' style='#{tbl_style}'#{tbl_attrib}>"
				cols = []
				rows = 0
				rc = 0
				@lines.each do |line|
					ccount = 0
					if line[0] == '/' && rows == 0
						cols = line[1..line.length].split('|')
						buff << "<thead><tr class='#{map['head.class']}'>"
						cols.each do |col|
							buff << "\t#{fmt_cell(col, true, ccount)}"
							ccount += 1
						end
						buff << '</tr></thead>'
						buff << '<tbody>'
					elsif line[0] == '/'
						# implies footer
						cols = line[1..line.length].split('|')
						buff << "<tfoot><tr class='#{map['foot.class']}'>"
						cols.each do |col|
							buff << "\t#{fmt_cell(col, true, ccount)}"
							ccount += 1
						end
						buff << '</tr></tfoot>'
					elsif line[0] == '|' || line[0..1] == '|>'
						idx = 1
						sep = /(?<!\\)\|/
						if line[1] == '>'
							idx = 2
							sep = /(?<!\\)\|\>/
						end
						cols = line[idx..line.length].split(sep)
						@proc.vars['t.row'] = rc
						rclass = row_classes[rc % row_classes.length]
						buff << "<tr class='tr-row-#{rc} #{rclass}'>"
						cols.each do |col|
							buff << "\t#{fmt_cell(col, false, ccount)}"
							ccount += 1
						end
						buff << '</tr>'
						rc += 1
					else
						cols = line[1..line.length].split('|') if line[0] == '\\'
					end
					rows += 1
				end

				buff << '</tbody>'
				if cols.length > 0
					# @todo process footer
				end
				buff << "</table>"
				@proc.vars['table.class'] = ''
				@proc.vars['table.style'] = ''
				@proc.vars['table.attribs'] = ''
			end
			ret
		end

		def do_dt(line, buff, indents = '', indent_level = 0)
			ret = COLLECT
			if line == '' || line[0] != '>'
				ret = DONE
				ret = RETRY if line[0] != '>'

				buff << "<dl class='#{@proc.vars['dd.class']}'>"
				@lines.each do |line|
					key = line[0]
					val = line[1]
					buff << "<dt class='#{@proc.vars['dt.class']}'>#{key}</dt><dd class='#{@proc.vars['dd.class']}'>#{val}</dd>"
				end
				buff << "</dl>"
			else
				@lines << line[1..-1].split('::', 2)
				ret = COLLECT
			end
			ret
		end

		def do_default(line, buff, indents = '', indent_level = 0)
			ret = COLLECT
			blank = false

			raw = @type == 'raw'
			pre = @type == 'pre'
			nofmt = raw

			# we need to group indented lines as part of block, especially if it's otherwise empty
			if raw || pre || @type == 'bq'
				raw = true
				# strip off first indent
				if indent_level > 0
					#idx = indents.length / indent_level
					line = indents + line
					if pre
						line = "\n#{line}"
					elsif line == ''
						line = ' '
					end
				else
					blank = line == ''
					if pre
						line = "\n#{line}"
					end
				end
			else
				blank = line == ''
			end

			if blank
				@lines.delete('')
				start_tag = ''
				end_tag = ''
				if @type != 'raw'
					bp = @block_params[@type]
					@type = 'blockquote' if @type == 'bq'
					# @todo get attributes from block param
					start_tag = "<#{@type} class='#{bp['class']}' style='#{bp['style']}'>"
					end_tag = "</#{@type}>"
					join = @type == 'pre' ? "" : "<br />\n"

					buff << "#{start_tag}#{@lines.join(join)}#{end_tag}"
				else
					buff << @lines.join("\n")
				end
				@lines = []
				ret = DONE
			else
				line = !nofmt ? @proc.fmt_line(line) : @proc.expand_expr(line)
				@lines << line
				ret = raw ? COLLECT_RAW : COLLECT
			end
			ret
		end

		def fmt_cell(val, header = false, colnum = 0)
			tag = header ? 'th' : 'td'
			buff = []
			attribs = ''

			if val[0] == '\\'
				val = val[1..val.length]
			elsif val[0] == CELL_ATTR_START
				rt = val.index(CELL_ATTR_END)
				if rt
					attribs = val[1...rt]
					val = val[rt+CELL_ATTR_END.length..val.length]
				end
			end

			# inject column position via class
			olen = attribs.length
			attribs = attribs.gsub(/class=(['"])/, 'class=$1' + "td-col-#{colnum}")
			if olen == attribs.length
				attribs += " class='td-col-#{colnum}'"
			end

			buff << "<#{tag} #{attribs}>"
			cclass = 
			if val[0] == '\\'
				val = val[1..val.length]
			end

			buff << @proc.fmt_line(val)
			buff << "</#{tag}>"
			return buff.join('')
		end
	end
	
	class InlineMacros
		include Eggshell::MacroHandler

		def initialize
			@capvar = nil
			@collbuff = nil
			@depth = 0
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

		def set_processor(eggshell)
			@proc = eggshell
			@proc.register_macro(self, '[!', '[~', '[^', '[.', '[*', '[**', '[/', '[//', '[_', '[-')
		end

		def process(buffer, macname, args, lines, depth)
			prefix = macname[0..1]
			textpart = args.shift
			tag = nil

			case prefix
			when '[^'
				tag = 'sup'
			when '[.'
				tag = 'sup'
			when '[*'
				tag = macname == '[**' ? 'strong' : 'b'
			when '[/'
				tag = macname == '[//' ? 'em' : 'i'
			when '[-'
				tag = 'strike'
			when '[_'
				tag = 'u'
			when '[~'
				tag = 'a'
				link = textpart
				text = nil
				if link == ''
					text = ''
				else
					textpart, link = link.split('; ')
					link = '' if !link
					args.unshift('href:'+link)
				end
			when '[!'
				tag = 'img'
				args.unshift('src:'+textpart)
				textpart = nil
			end
			
			buffer << restructure_html(tag, textpart, args)
		end
		
		def restructure_html(tag, text, attributes = [])
			buff = "<#{tag}"
			attributes.each do |attrib|
				key, val = attrib.split(':', 2)
				# @todo html escape?
				if val
					buff = "#{buff} #{key}=\"#{val.gsub('\\|', '|')}\""
				else
					buff = "#{buff} #{key}"
				end
			end

			if text == nil
				buff += ' />'
			else
				buff = "#{buff}>#{text}</#{tag}>"
			end
			buff
		end
	end	

	# Macros:
	# 
	# - `include`
	# - `capture`
	# - `var`
	class BasicMacros
		include Eggshell::MacroHandler

		def initialize
			@capvar = nil
			@collbuff = nil
			@depth = 0
		end

		def set_processor(eggshell)
			@proc = eggshell
			@proc.register_macro(self, *%w(! = capture var include process parse_test))
		end

		def process(buffer, macname, args, lines, depth)
			if macname == '!'
				@proc.vars[:block_params] = @proc.expr_eval(args)
			elsif macname == 'process'
				if args[0]
					proclines = @proc.expr_eval(args[0])
					proclines = proclines.split(/[\r\n]+/) if proclines.is_a?(String)
					buffer << @proc.process(proclines, depth + 1) if proclines.is_a?(Array)
				end
			elsif macname == 'capture'
				# @todo check args for fragment to parse
				return if !lines
				var = args[0]
				@proc.vars[var] = @proc.process(lines, depth)
			elsif macname == 'var' || macname == '='
				# @todo support multiple vars via lines
				# @todo expand value if expression
				if args.length >= 2
					key = args[0]
					val = args[1]
					if val.is_a?(Array)
						if val[0] == :str
							val = val[1]
						elsif val[1] == :var
							val = @proc.vars[val[2]]
						else
							# @todo operator?
						end
					end
					@proc.vars[key] = val
				end
			elsif macname == 'include'
				paths = args[0]
				opts = args[1] || {}
				if opts['encoding']
					opts[:encoding] = opts['encoding']
				else
					opts[:encoding] = 'utf-8'
				end
				if lines && lines.length > 0
					paths = lines
				end
				do_include(paths, buffer, depth, opts)
			end
		end

		def do_include(paths, buff, depth, opts = {})
			paths = [paths] if !paths.is_a?(Array)
			# @todo check all include paths?
			paths.each do |inc|
				inc = @proc.expand_expr(inc.strip)
				checks = []
				if inc[0] != '/'
					@proc.vars[:include_paths].each do |root|
						checks << "#{root}/#{inc}"
					end
					# @todo if :include_root, expand path and check that it's under the root, otherwise, sandbox
				else
					# sandboxed root include
					if @proc.vars[:include_root]
						checks << "#{@proc.vars[:include_root]}#{inc}"
					else
						checks << inc
					end
				end

				checks.each do |inc|
					if File.exists?(inc)
						lines = IO.readlines(inc, $/, opts)
						buff << @proc.process(lines, depth + 1)
						@proc._debug("include: 200 #{inc}")
						break
					else
						@proc._warn("include: 404 #{inc}")
					end
				end
			end
		end
	end

	class ControlMacros
		include Eggshell::MacroHandler

		def initialize
			@stack = []
			@state = []
			@macstack = []
		end

		def set_processor(eggshell)
			@proc = eggshell
			@proc.register_macro(self, *%w(if elsif else loop for while break next))
		end

		def process(buffer, macname, args, lines, depth)
			p0 = args.is_a?(Array) ? args[0] : nil
			lines ? lines.delete('') : ''

			macname = macname.to_sym
			st = @state[depth]
			if !@state[depth]
				st = {:type => macname}

				@state[depth] = st
				# erase nested state
				@state[depth+1] = nil
			end

			if macname == :for || macname == :loop
				p0 = p0 || {}
				st[:var] = p0['var']
				st[:start] = p0['start']
				st[:stop] = p0['stop']
				st[:step] = p0['step'] || 1
				st[:iter] = p0['items'] || 'items'
				st[:item] = p0['item'] || 'item'
				st[:counter] = p0['counter'] || 'counter'
				st[:raw]  = p0['raw'] # @todo inherit if not set?

				mbuff = []
				looper = nil
				loop_is_map = false

				# in for, construct range that can be looped over
				# in loop, detect 'each' method
				if macname == :for
					st[:item] = st[:var]
					looper = Range.new(st[:start], st[:stop]).step(st[:step]).to_a
				elsif macname == :loop
					begin
						looper = st[:iter].is_a?(Array) && st[:iter][0].is_a?(Symbol) ? @proc.expr_eval(st[:iter]) : st[:iter]
						looper = nil if !looper.respond_to?(:each)
						loop_is_map = looper.is_a?(Hash)
					rescue
					end
				end

				if looper
					counter = 0
					looper.each do |i1, i2|
						# for maps, use key as the counter
						val = nil
						if loop_is_map
							@proc.vars[st[:counter]] = i1
							val = i2
						else
							val = i1
							@proc.vars[st[:counter]] = counter
						end

						@proc.vars[st[:item]] = val.is_a?(Array) && val[0].is_a?(Symbol) ? @proc.expr_eval(val) : val
						process_lines(lines, buffer, depth + 1, st[:raw])
						break if st[:break]

						counter += 1
					end
				end

				# clear state
				@state[depth] = nil
			elsif macname == :while
				raw = args[1]
				while @proc.expr_eval(p0)
					process_lines(lines, buffer, depth + 1, raw)
					break if st[:break]
				end
			elsif macname == :if || macname == :elsif || macname == :else
				cond = p0
				st[:if] = true if macname == :if
				if st[:cond_count] == nil || macname == :if
					st[:cond_count] = 0 
					st[:cond_eval] = false
					st[:cond_met] = false
				end

				last_action = st[:last_action]
				st[:last_action] = macname.to_sym

				# @todo more checks (e.g. no elsif after else, no multiple else, etc.)
				if !st[:if] || (macname != :else && !cond)
					# @todo exception?
					return
				end

				if macname != :else
					if !st[:cond_eval]
						cond_struct = Eggshell::ExpressionEvaluator.struct(cond)
						st[:cond_eval] = @proc.expr_eval(cond_struct)[0]
					end
				else
					st[:cond_eval] = true
				end

				if st[:cond_eval] && !st[:cond_met]
					st[:cond_met] = true
					process_lines(lines, buffer, depth + 1)
				end
			elsif macname == :break
				lvl = p0 || 1
				i = depth - 1

				# set breaks at each found loop until # of levels reached
				while i >= 0
					st = @state[i]
					i -= 1
					next if !st
					if st[:type] == :for || st[:type] == :while || st[:type] == :loop
						lvl -= 1
						st[:break] = true
						break if lvl <= 0
					end
				end
			elsif macname == :next
				lvl = p0 || 1
				i = depth - 1

				# set breaks at each found loop until # of levels reached
				while i >= 0
					st = @state[i]
					i -= 1
					next if !st
					if st[:type] == :for || st[:type] == :while || st[:type] == :loop
						lvl -= 1
						st[:next] = true
						break if lvl <= 0
					end
				end
			end
		end

		def process_lines(lines, buffer, depth, raw = false)
			return if !lines
			ln = []
			lines.each do |line|
				if line.is_a?(Eggshell::Block)
					if ln.length > 0
						buffer << (raw ? @proc.expand_expr(ln.join("\n")) : @proc.process(ln, depth))
						ln = []
					end
					line.process(buffer, depth)
					if @state[depth-1][:next]
						@state[depth-1][:next] = false
						break
					end
				else
					ln << line
				end
			end
			if ln.length > 0
				buffer << (raw ? @proc.expand_expr(ln.join("\n")) : @proc.process(ln, depth))
			end
		end

		protected :process_lines
	end

	# Baseline functions.
	# @todo catch exceptions???
	module StdFunctions
		# Repeats `str` by a given `amt`
		def self.str_repeat(str, amt)
			return str * amt
		end

		FUNC_NAMES = %w(str_repeat).freeze
	end

	include Eggshell::Bundles::Bundle
end
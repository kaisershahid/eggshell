class TMD::Bundles::Basics
	BUNDLE_ID = 'basics'

	def self.new_instance(proc, opts = nil)
		bbasics = BasicBlocks.new
		mbasics = BasicMacros.new
		mcntrls = ControlMacros.new

		bbasics.set_processor(proc)
		mbasics.set_processor(proc)
		mcntrls.set_processor(proc)
	end

	# `table` block parameters:
	# - `row.classes`: defaults to `['odd', 'even']`. The number of elements represents the number of cycles.
	class BasicBlocks
		include TMD::BlockHandler

		CELL_ATTR_START = '!'
		CELL_ATTR_END = '<!'

		def set_processor(proc)
			@proc = proc
			@proc.register_block(self, *%w(h1 h2 h3 h4 h5 h6 hr table pre p bq div raw # - / | >))
		end

		def start(name, line, buffer, indents = '', indent_level = 0)
			# @todo read block_param arguments
			if name[0] == 'h'
				if name == 'hr'
					buff << "<hr />"
				else
					id = line.downcase.strip.gsub(/[^a-z0-9_-]+/, '-')
					buffer << "<#{name} id='#{id}'>#{line}</#{name}>"
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
				@lines << line if line != 'table'
				return COLLECT
			end

			if name == '>'
				@type = :dt
				@lines = [line[1..-1].split('::', 2)]
				return COLLECT
			end

			# assume block text
			@type = name
			if line.index(name) == 0
				line = line[name.length+1..-1].lstrip
			end
			@lines = [@proc.fmt_line(line)]

			return COLLECT
		end

		def collect(line, buff, indents = '', indent_level = 0)
			line = '' if !line
			ret = COLLECT
			if @type == :list
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
			elsif @type == :table
				if line[0] == '|' || line[0] == '/'
					@lines << line
				else
					ret = (line[0] != '\\' && line != '') ? RETRY : DONE
					params = @proc.vars[:block_params]
					map = params.is_a?(Array) ? (params[0] || {}) : {}
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
					cols = nil
					rows = 0
					rc = 0
					@lines.each do |line|
						cols = []
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
							sep = '|'
							if line[1] == '>'
								idx = 2
								sep = '|>'
							end
							cols = line[idx..line.length].split(sep)
							@proc.vars['t.row'] = rc
							rclass = row_classes[rc % row_classes.length]
							buff << "<tr class='#{rc} #{rclass}'>"
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
			elsif @type == :dt
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
			else
				blank = false
				if @type == 'pre'
					#$stderr.write "(#{indent_level}) #{indents}|#{line}\n"
					if indent_level > 0
						idx = indents.length / indent_level
						line = indents[idx..-1] + line
						#$stderr.write " #{indent_level}) #{indents}|#{line}\n"
					else
						blank = line == ''
					end
				else
					blank = line == ''
				end

				if blank
					start_tag = ''
					end_tag = ''
					if @type != 'raw'
						@type = 'blockquote' if @type == 'bq'
						# @todo get attributes from block param
						start_tag = "<#{@type}>"
						end_tag = "</#{@type}>"
						join = @type == 'pre' ? "\n" : '<br />'
							
						buff << "#{start_tag}#{@lines.join(join)}#{end_tag}"
					else
						buff << @lines.join("\n")
					end
					@lines = []
					ret = DONE
				else
					@lines << @proc.fmt_line(line)
					ret = COLLECT
				end
			end
			return ret
		end

		def fmt_cell(val, header = false, colnum = 0)
			tag = header ? 'th' : 'td'
			buff = []
			attribs = ''

			if val[0] == '\\'
				val = val[1..val.length]
			elsif val[0] == CELL_ATTR_START
				rt = val.index(CELL_ATTR_END, 1)
				attribs = val[1...rt]
				val = val[rt+CELL_ATTR_END.length..val.length]
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

	# Macros:
	# 
	# - `include`
	# - `capture`
	# - `var`
	class BasicMacros
		include TMD::MacroHandler

		def initialize
			@capvar = nil
			@collbuff = nil
			@depth = 0
		end

		def set_processor(tmd)
			@proc = tmd
			@proc.register_macro(self, *%w(! capture var include process parse_test))
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
			elsif macname == 'var'
				# @todo support multiple vars via lines
				# @todo expand value if expression
				if args.length >= 2
					key = args[0][1]
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
				if lines && lines.length > 0
					paths = lines
				end
				do_include(paths, buffer, depth)
			end
		end

		def do_include(paths, buff, depth)
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
						lines = IO.readlines(inc)
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
		include TMD::MacroHandler

		def initialize
			@stack = []
			@state = []
			@macstack = []
		end

		def set_processor(tmd)
			@proc = tmd
			@proc.register_macro(self, *%w(if elsif else loop for while))
		end

		def process(buffer, macname, args, lines, depth)
			p0 = args.is_a?(Array) ? args[0] : nil

			st = @state[depth]
			if !@state[depth]
				st = {}

				@state[depth] = st
				# erase nested state
				@state[depth+1] = nil
			end

			if macname == 'for' || macname == 'loop' || macname == 'while'
				st[:var] = p0['var']
				st[:start] = p0['start']
				st[:stop] = p0['end']
				st[:step] = p0['step'] || 1
				st[:iter] = nil
				st[:item] = p0['item'] || 'item'

				mbuff = []
				if macname == 'for'
					#puts "for: #{st[:var]}=#{st[:start]} (#{st[:start.class]}) / step=#{st[:step]} #{st[:step.class]}"
					@proc.vars[st[:var]] = st[:start]

					bf = []
					ln = []
					while (@proc.vars[st[:var]] <= st[:stop])
						#puts "#{var} => #{@proc.vars[var]} #{@proc.vars[var].class}"
						#puts "\t\t" +lines.inspect
						#buffer << @proc.process(lines, depth + 1)
						lines.each do |line|
							if line.is_a?(TMD::Block)
								if ln.length > 0
									buffer << @proc.process(ln, depth + 1)
									ln = []
								end
								line.process(buffer, depth + 1)
							else
								ln << line
							end
						end
						if ln.length > 0
							buffer << @proc.process(ln, depth + 1)
						end

						@proc.vars[st[:var]] += st[:step]
					end
				else
					buffer << "-- defer #{macname} (#{depth})"
				end
			elsif macname == 'if' || macname == 'elsif' || macname == 'else'
				cond = p0
				st[:if] = true if macname == 'if'
				if st[:cond_count] == nil || macname == 'if'
					st[:cond_count] = 0 
					st[:cond_eval] = false
					st[:cond_met] = false
				end

				last_action = st[:last_action]
				st[:last_action] = macname.to_sym

				# @todo more checks (e.g. no elsif after else, no multiple else, etc.)
				if !st[:if] || (macname != 'else' && !cond)
					# @todo exception?
					return
				end

				if macname != 'else'
					if !st[:cond_eval]
						cond = TMD::ExpressionEvaluator.struct(cond)
						st[:cond_eval] = @proc.expr_eval(cond)[0]
						#puts "cond = #{cond.inspect}\n\teval=#{st[:cond_eval]}"
					end
				else
					st[:cond_eval] = true
				end

				if st[:cond_eval] && !st[:cond_met]
					st[:cond_met] = true
					ln = []
					lines.each do |line|
						if line.is_a?(TMD::Block)
							if ln.length > 0
								buffer << @proc.process(ln, depth + 1)
								ln = []
							end
							line.process(buffer, depth + 1)
						else
							ln << line
						end
					end
					if ln.length > 0
						buffer << @proc.process(ln, depth + 1)
					end
				end
			end
		end
	end

	include TMD::Bundles::Bundle
end
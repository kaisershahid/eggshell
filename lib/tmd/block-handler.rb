module TMD::BlockHandler
	# Indicates that subsequent lines should be collected.
	COLLECT = :collect
	# Indicates that the current line ends the block and all collected
	# lines should be processed.
	DONE = :done
	# A variant of DONE: if the current line doesn't conform to expected structure,
	# process the previous lines and indicate to processor that a new block has
	# started.
	RETRY = :retry

	def set_processor(proc)
	end

	def start(name, line, buffer, indents = '', indent_level = 0)
	end

	def collect(line, buffer)
	end

	module Defaults
		class NoOpHandler
			include TMD::BlockHandler
		end
		class BasicHtml
			include TMD::BlockHandler

			def set_processor(proc)
				@proc = proc
				@proc.register_block(self, 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'table', 'pre', 'p', 'bq', 'div', 'raw', '#', '-', '/', '|')
			end

			def start(name, line, buffer, indents = '', indent_level = 0)

				# @todo read block_param arguments
				if name[0] == 'h'
					if name == 'hr'
						buff << "<hr />"
					else
						id = line.downcase.strip.gsub(/[^a-z0-9_-]+/, '-')
						buff << "<#{name} id='#{id}'>#{line}</#{name}>"
					end
					return DONE
				end

				if name == '#' || name == '-'
					@type = :list
					@lines = [[name + line, indent_level]]
					return COLLECT
				end

				if name == 'table' || name == '/' || name == '|'
					@type = :table
					line = name + line if line != 'table'
					@lines = [line]
					return COLLECT
				end

				# assume block text
				@type = name
				@lines = [line]

				return COLLECT
			end

			def collect(line, buff, indents = '', indent_level = 0)
				line = '' if !line
				ret = COLLECT
				if @type == :list
					if line && (line[0] == '#' || line[0] = '-')
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

						@proc.vars['t.row'] = 0
						buff << "<table class='#{@proc.vars['table.class']}' style='#{@proc.vars['table.style']}' #{@proc.vars['table.attribs']}>"
						cols = nil
						@lines.each do |line|
							cols = []
							if line[0] == '/'
								cols = line[1..line.length].split('|')
								buff << '<thead><tr>'
								cols.each do |col|
									buff << "\t#{@proc.fmt_cell(col, true)}"
								end
								buff << '</tr></thead>'
								buff << '<tbody>'
							elsif line[0] == '|' || line[0..1] == '|>'
								idx = 1
								sep = '|'
								if line[1] == '>'
									idx = 2
									sep = '|>'
								end
								cols = line[idx..line.length].split(sep)
								@proc.vars['t.row'] += 1
								buff << '<tr>'
								cols.each do |col|
									buff << "\t#{@proc.fmt_cell(col)}"
								end
								buff << '</tr>'
							else
								cols = line[1..line.length].split('|') if line[0] == '\\'
							end
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
				else
					if line == ''
						start_tag = ''
						end_tag = ''
						if @type != 'raw'
							@type = 'blockquote' if !@type == 'bq'
							# @todo get attributes from block param
							start_tag = "<#{@type}>"
							end_tag = "</#{@type}>"
							buff << "#{start_tag}#{@lines.join('<br />')}#{end_tag}"
						else
							# @todo insert newlines?
							buff << @lines.join('')
						end
						@lines = []
						ret = DONE
					else
						@lines << line
						ret = COLLECT
					end
				end
				return ret
			end
		end
	end
end
module Eggshell::Bundles::Basic
	BUNDLE_ID = 'basics'
	EE = Eggshell::ExpressionEvaluator
	BH = Eggshell::BlockHandler
	MH = Eggshell::MacroHandler
	FH = Eggshell::FormatHandler

	def self.new_instance(proc, opts = nil)
		TextBlocks.new.set_processor(proc, opts)
		TableBlock.new.set_processor(proc, opts)
		ListBlocks.new.set_processor(proc, opts)
		SectionBlocks.new.set_processor(proc, opts)
		
		CoreMacros.new.set_processor(proc, opts)
		ControlLoopMacros.new.set_processor(proc, opts)
		
		BasicFormatHandlers.new.set_processor(proc, opts)

		#proc.register_functions('', StdFunctions::FUNC_NAMES)
		proc.register_functions('sprintf', Kernel)
	end

	class TextBlocks
		include BH
		include BH::BlockParams
		include BH::HtmlUtils
		
		# HTML tags that have end-block checks. any block starting with one of these tags will have
		# its contents passed through until end of the tag (essentially, raw)
		# @todo what else should be treated?
		HTML_BLOCK = /^<(style|script|table|dl|select|textarea|\!--|\?)/
		HTML_BLOCK_END = {
			'<!--' => '-->',
			'<?' => '\\?>'
		}.freeze
		
		# For lines starting with only these tags, accept as-is
		HTML_PASSTHRU = /^\s*<(\/?(html|head|meta|link|title|body|br|section|div|blockquote|p|pre))/

		def initialize
			@block_types = ['p', 'bq', 'pre', 'div', 'raw', 'html_pass', 'html_block']
		end

		START_TEXT = /^(p|bq|pre|raw|div)[(.]/
		
		def can_handle(line)
			match = START_TEXT.match(line)
			if match
				@block_type = match[1]
				if @block_type == 'pre' || @block_type == 'raw'
					return BH::COLLECT_RAW
				else
					return BH::COLLECT
				end
			end
			
			if line.match(HTML_PASSTHRU)
				@block_type = 'html_pass'
				return BH::DONE
			end
			
			html = line.match(HTML_BLOCK)
			if html
				@block_type = 'html_block'

				end_html = HTML_BLOCK_END["<#{html[1]}"]
				end_html = "</#{html[1]}>$" if !end_html
				if line.match(end_html)
					return BH::DONE
				end

				@end_html = end_html
				return BH::COLLECT_RAW
			end

			return BH::RETRY
		end
		
		def continue_with(line)
			if @block_type == 'html_block'
				done = line.match(@end_html)
				if done
					return BH::DONE
				else
					return BH::COLLECT
				end
			else
				if @block_type == 'pre' || @block_type == 'raw'
					if line && line != ''
						return BH::COLLECT
					end
				elsif line
					if line == '' || line.match(HTML_PASSTHRU) != nil || line.match(HTML_BLOCK) != nil
						return BH::RETRY
					end
					return BH::COLLECT
				end
			end

			return BH::RETRY
		end

		def process(type, args, lines, out, call_depth = 0)
			buff = []

			if type == 'html_pass' || type == 'html_block'
				out << @eggshell.expand_expr(lines.join("\n"))
			else
				tagname = type == 'bq' ? 'blockquote' : type
				args = [] if !args
				bp = get_block_params(type, args[0])
				raw = type == 'pre' || type == 'raw'

				line_break = raw ? '' : '<br />'
				lines.each do |line|
					str = line.is_a?(Eggshell::Line) ? line.to_s : line
					str.chomp!
					buff << str
				end

				# @todo don't call expand_expr if raw && args[0]['no_expand']?
				buff = buff.join("#{line_break}\n")
				buff = @eggshell.expand_formatting(buff) if !raw
				buff = @eggshell.unescape(@eggshell.expand_expr(buff))
				
				if type != 'raw'
					out << [create_tag(type, bp), buff, "</#{type}>"].join('')
				else
					out << buff
				end
			end
		end
	end

	"""
	/head|head
	!caption:caption text|att=val|att=val
	!col:att=val|att=val
	|col|col|col
	|>col|>col|>col
	|!@att=val att2=val2@!col|col
	/foot|foot
	"""
	class TableBlock
		include BH
		include BH::BlockParams
		include BH::HtmlUtils
		include FH::Utils
		
		def initialize
			@block_types = ['table']
		end

		# @todo support opening row with !@ (which would then get applied to <tr>)
		# @todo support thead/tbody/tfoot attributes? maybe these things can be handled same as how caption/colgroup is defined
		DELIM1 = '|'
		DELIM2 = '|>'
		HEADER = '/'
		SPECIAL_DEF = /^!(\w+):(.+$)/
		CELL_ATTR_START = '!@'
		CELL_ATTR_IDX = 1
		CELL_ATTR_END = '@!'

		def can_handle(line)
			if !@block_type
				if line.match(/^(table[(.]?|\||\|>|\/)/) || line.match(SPECIAL_DEF)
					@block_type = 'table'
					return BH::COLLECT
				end
			end
			return BH::RETRY
		end

		def continue_with(line)
			if line.match(/^(\||\|>|\/)/) || line.match(SPECIAL_DEF)
				return BH::COLLECT
			end
			return BH::RETRY
		end

		T_ROW = 't.row'
		def process(type, args, lines, out, call_depth = 0)
			args = [] if !args
			bp = get_block_params(type, args[0])
			row_classes = bp['row.classes']
			row_classes = ['odd', 'even'] if !row_classes.is_a?(Array)
			
			o_out = out
			out = []

			@eggshell.vars[T_ROW] = 0
			out << create_tag('table', bp)
			out << "%caption%\n%colgroup%"
			caption = {:text => '', :atts => {}}
			colgroup = []

			cols = []
			rows = 0
			rc = 0
			data_started = false

			lines.each do |line_obj|
				ccount = 0
				line = line_obj.line
				special = line.match(SPECIAL_DEF)
				if special
					type = special[1]
					atts = special[2]
					if type == 'caption'
						text, atts = atts.split('|', 2)
						caption[:text] = text
						caption[:attributes] = parse_args(atts, true)[0]
					else
						atts = parse_args(atts, true)[0]
						puts atts.inspect
						colgroup << create_tag('col', attrib_string(atts), false)
					end
				elsif line[0] == '/' && rc == 0
					cols = line[1..line.length].split('|')
					out << "<thead><tr class='#{bp['head.class']}'>"
					cols.each do |col|
						out << "\t#{fmt_cell(col, true, ccount)}"
						ccount += 1
					end
					out << '</tr></thead>'
				elsif line[0] == '/'
					# implies footer
					out << '</tbody>' if rc > 0
					cols = line[1..line.length].split('|')
					out << "<tfoot><tr class='#{bp['foot.class']}'>"
					cols.each do |col|
						out << "\t#{fmt_cell(col, true, ccount)}"
						ccount += 1
					end
					out << '</tr></tfoot>'
					break
				elsif line[0] == DELIM1 || line[0..1] == DELIM2
					out << '<tbody>' if rc == 0
					idx = 1
					sep = /(?<!\\)\|/
					if line[1] == '>'
						idx = 2
						sep = /(?<!\\)\|\>/
					end
					cols = line[idx..line.length].split(sep)
					@eggshell.vars[T_ROW] = rc
					rclass = row_classes[rc % row_classes.length]
					out << "<tr class='tr-row-#{rc} #{rclass}'>"
					cols.each do |col|
						out << "\t#{fmt_cell(col, false, ccount)}"
						ccount += 1
					end
					out << '</tr>'
					rc += 1
				else
					cols = line[1..line.length].split('|') if line[0] == '\\'
				end
				rows += 1
			end

			out << "</table>"

			if caption[:text] != ''
				out[1].gsub!('%caption%', create_tag('caption', attrib_string(caption[:attributes]), true, caption[:text]))
			else
				out[1].gsub!("%caption%\n", '')
			end

			if colgroup.length > 0
				out[1].gsub!('%colgroup%', "<colgroup>\n\t#{colgroup.join("\n\t")}\n</colgroup>")
			else
				out[1].gsub("%colgroup%\n", '')
			end
			
			o_out << out.join("\n")
		end

		def fmt_cell(val, header = false, colnum = 0)
			tag = header ? 'th' : 'td'
			buff = []
			attribs = ''

			if val[0] == '\\'
				val = val[1..val.length]
			elsif val[0..CELL_ATTR_IDX] == CELL_ATTR_START
				rt = val.index(CELL_ATTR_END)
				if rt
					attribs = val[CELL_ATTR_IDX+1...rt]
					val = val[rt+CELL_ATTR_END.length..val.length]
				end
			end

			# inject column position via class
			olen = attribs.length
			match = attribs.match(/class=(['"])([^'"]*)(['"])/)
			if !match
				attribs += " class='td-col-#{colnum}'"
			else
				attribs = attribs.gsub(match[0], "class='#{match[2]} td-col-#{colnum}'")
			end

			buff << "<#{tag} #{attribs}>"
			cclass = 
			if val[0] == '\\'
				val = val[1..val.length]
			end

			buff << @eggshell.expand_formatting(val)
			buff << "</#{tag}>"
			return buff.join('')
		end
	end
	
	class ListBlocks
		include BH
		include BH::BlockParams
		include BH::HtmlUtils
		
		def initialize
			@block_types = ['ul', 'ol', 'dl']
		end

		START_LIST = /^(ol|ul|dl)[(.]/
		START_LIST_SHORT = /^\s*([#>-])/

		def can_handle(line)
			match = START_LIST.match(line)
			if match
				@block_type = match[1]
				return BH::COLLECT
			end

			match = START_LIST_SHORT.match(line)
			if match
				if match[1] == '>'
					@block_type = 'dl'
				else
					@block_type = match[1] == '-' ? 'ul' : 'ol'
				end
				return BH::COLLECT
			end
			
			return BH::RETRY
		end
		
		def continue_with(line)
			if line == nil || line == "" || !START_LIST_SHORT.match(line)
				return BH::RETRY
			else
				return BH::COLLECT
			end
		end

		# @todo support ability to add attributes to sub-lists (maybe '[-#] @\(....\)')
		def process(type, args, lines, out, call_depth = 0)
			if type == 'dl'
				# @todo
			else
				order_stack = []
				otype_stack = []
				last = nil
				first_type = nil

				if lines[0] && !lines[0].line.match(/[-#]/)
					line = lines.shift
				end

				lines.each do |line_obj|
					line = line_obj.line
					indent = line_obj.indent_lvl
					ltype = line[0] == '-' ? 'ul' : 'ol'
					line = line[1..line.length].strip

					if order_stack.length == 0
						# use the given type to start; infer for sub-lists
						order_stack << create_tag(type, get_block_params(type, args[0]))
						otype_stack << type
					# @todo make sure that previous item was a list
					# remove closing li to enclose sublist
					elsif indent > (otype_stack.length-1) && order_stack.length > 0
						last = order_stack[-1]
						last = last[0...last.length-5]
						order_stack[-1] = last

						order_stack << "#{"\t"*indent}<#{ltype}>"
						otype_stack << ltype
					elsif indent < (otype_stack.length-1)
						count = otype_stack.length - 1
						while count > indent
							ltype = otype_stack.pop	
							order_stack << "#{"\t"*count}</#{ltype}>\n#{"\t"*(count-1)}</li>"
							count -= 1
						end
					end
					order_stack << "#{"\t"*indent}<li>#{line}</li>"
				end

				# close nested lists
				d = otype_stack.length
				c = 1
				otype_stack.reverse.each do |ltype|
					ident = d - c
					order_stack << "#{"\t" * ident}</#{ltype}>\n#{ident-1 >= 0 ? "\t"*(ident-1) : ''}#{c == d ? '' : "</li>"}"
					c += 1
				end
				out << @eggshell.expand_all(order_stack.join("\n"))
			end
		end
	end

	class SectionBlocks
		include BH
		include BH::BlockParams
		include BH::HtmlUtils

		SECTION ='section'
		SECTION_END = 'section-end'
		TOC_TEMPLATE = {
			:default => "<div class='toc-h$level'><a href='\#$id'>$title</a></div>"
		}

		def initialize
			@block_types = ['h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'hr', SECTION, SECTION_END, 'toc']
			@header_list = []
			@header_idx = {}
		end

		START = /^(h[1-6]|section|toc)[(.]/

		def can_handle(line)
			match = START.match(line)
			if match
				@block_type = match[1]
				return @block_type != 'toc' ? BH::DONE : BH::COLLECT
			end
			return BH::RETRY
		end

		def process(type, args, lines, out, call_depth = 0)
			bp = get_block_params(type, args[0])
			line = lines[0]
			line = line.line.strip if line.is_a?(Eggshell::Line)

			if type[0] == 'h'
				if type == 'hr'
					out << create_tag(type, bp, false)
				else
					lvl = type[1].to_i

					# assign unique id
					id = bp['id'] || line.downcase.strip.gsub(/[^a-z0-9_-]+/, '-')
					lid = id
					i = 1
					while @header_idx[lid] != nil
						lid = "#{id}-#{i}"
						i += 1
					end
					id = lid
					bp['id'] = id
					title = @eggshell.expand_formatting(line)

					out << "#{create_tag(type, bp)}#{title}</#{type}>"

					@header_list << {:level => lvl, :id => lid, :title => title, :tag => type}
					@header_idx[lid] = @header_list.length - 1
				end
			elsif type == SECTION
				out << create_tag(SECTION, bp)
				@header_list << type
			elsif type == SECTION_END
				out << '</section>'
				@header_list << type
			elsif type == 'toc'
				# first, parse the toc definitions from lines
				toc_template = TOC_TEMPLATE.clone
				lines.each do |line_obj|
					line = line_obj.is_a?(Eggshell::Line) ? line_obj.line : line
					key, val = line.split(':', 2)
					toc_template[key.to_sym] = val
				end

				# now go through collected headers and sections and generate toc
				out << @eggshell.expand_formatting(toc_template[:start]) if toc_template[:start]
				@header_list.each do |entry|
					if entry == SECTION
						out << @eggshell.expand_formatting(toc_template[:section]) if toc_template[:section]
					elsif entry == SECTION_END
						out << @eggshell.expand_formatting(toc_template[:section_end]) if toc_template[:section_end]
					elsif entry.is_a?(Hash)
						tpl = toc_template[entry[:tag]] || toc_template[:default]
						out << @eggshell.expand_formatting(
							tpl.gsub('$id', entry[:id]).gsub('$title', entry[:title]).gsub('$level', entry[:level].to_s)
						)
					end
				end
				out << @eggshell.expand_formatting(toc_template[:end]) if toc_template[:end]
			end
		end
	end
	
	class BasicFormatHandlers
		include FH
		include FH::Utils
		include BH::HtmlUtils
		
		TAG_MAP = {
			'[*' => 'b',
			'[**' => 'strong',
			'[/' => 'i',
			'[//' => 'em',
			'[__' => 'u',
			'[-' => 'strike',
			'[^' => 'sup',
			'[_' => 'sub',
			'[[' => 'span'
		}.freeze

		ESCAPE_MAP_HTML = {
			'<' => '&lt;',
			'>' => '&gt;',
			'/<' => '&laquo;',
			'>/' => '&raquo;',
			'/\'' => '&lsquo;',
			'\'/' => '&rsquo;',
			'/"' => '&ldquo;',
			'"/' => '&rdquo;',
			'c' => '&copy;',
			'r' => '&reg;',
			'!' => '&iexcl;',
			'-' => '&ndash;',
			'--' => '&mdash;',
			'&' => '&amp;'
		}.freeze
		
		def initialize
			@fmt_delimeters = [
				['[*', '*]'], # bold
				['[**', '**]'], # strong
				['[/', '/]'], # italic
				['[//', '//]'], # emphasis
				['[__', '__]'], # underline
				['[-', '-]'], # strike
				['[^', '^]'], # superscript
				['[_', '_]'], # subscript,
				['[[', ']]'], # span
				['[~', '~]'], # anchor
				['[!', '!]'], # image
				['%{', '}%', true], # entity expansion
				['`', '`', '%{'], # code, backtick
				['{{', '}}', '%{'] # code, normal
			]
		end

		def format(tag, str)
			if tag == '{{' || tag == '`'
				cls = tag == '{{' ? 'normal' : 'backtick'
				return "<code class='#{cls}'>#{str}</code>"
			elsif tag == '%{'
				# @todo find a way to expand char map and handle unmapped strings at runtime
				buff = ''
				str.split(' ').each do |part|
					c = ESCAPE_MAP_HTML[part]
					buff += c || part
				end
				return buff
			end
			
			st = tag[0..1]
			args = parse_args(str.strip)
			akey = BH::BlockParams::ATTRIBUTES
			atts = {akey => {}}
			atts[akey].update(args.pop)

			tagname = nil
			tagopen = true
			text = args[0]

			if tag == '[~'
				link, text = args
				link = '' if !link 
				text = '' if !text
				if text.strip == ''
					text = link
				end
				atts[akey]['href'] = link if link != ''
				tagname = 'a'
			elsif tag == '[!'
				link, alt = args
				link = '' if !link
				alt = '' if !alt
				
				atts[akey]['src'] = link if link != ''
				atts[akey]['alt'] = alt if alt != ''
				tagname = 'img'
				tagopen = false
			else
				tagname = TAG_MAP[tag]
			end

			if tagopen
				return "#{create_tag(tagname, atts)}#{text}</#{tagname}>"
			else
				return create_tag(tagname, atts, false)
			end
		end
	end

	# These macros are highly recommended to always be part of an instance of the processor.
	#
	# dl.
	# {{!}}:: sets default parameter values (block parameters) so that they don't have to be
	# specified for every block instance.
	# {{raw}}:: passes all block lines up into output chain. Macros are assembled before being
	# outputted.
	# {{pipe}}:: allows blocks to pipe into the adjacent block
	#
	# {{process}} always dynamic processing of content. This allows previous macros to build
	# up a document dynamically.
	class CoreMacros
		include MH
		include BH::BlockParams
		
		CAP_OUT = 'capture_output'

		def set_processor(proc, opts = nil)
			opts = {} if !opts
			@opts = opts
			@eggshell = proc
			@eggshell.add_macro_handler(self, '=', '!', 'process', 'capture', 'raw', 'pipe')
			@eggshell.add_macro_handler(self, 'include') if !@opts['macro.include.off']
			@vars = @eggshell.vars

			@vars[:include_stack] = []
			if opts['include.options']
				opts['include.options'].each do |k,v|
					@vars[k.to_sym] = v
				end
			end
			
			if @vars[:include_paths].length == 0
				@vars[:include_paths] = [Dir.getwd]
			end
		end

		def process(name, args, lines, out, call_depth = 0)
			if name == '='
				# @todo expand args[0]?
				if args[0]
					val = nil
					if args[1].is_a?(Array) && args[1][0].is_a?(Symbol)
						val = @eggshell.expr_eval(args[1])
					else
						val = args[1]
					end
					@eggshell.vars[args[0]] = val
				end
			elsif name == '!'
				block_name = args[0]
				block_params = args[1]
				set_block_params(block_name, block_params) if block_name
			elsif name == 'process'
				
			elsif name == 'capture'
				var = args[0] || CAP_OUT
				captured = @eggshell.assemble(lines, call_depth + 1)
				captured = @eggshell.expand_expr(captured)
				@eggshell.vars[var] = captured
			elsif name == 'include'
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
				do_include(paths, out, call_depth, opts)
			elsif name == 'raw'
				lines.each do |unit|
					if unit.is_a?(Array)
						if unit[0] == :block
							unit[Eggshell::ParseTree::IDX_LINES].each do |line|
								out << line.to_s
							end
						else
							out << @eggshell.assemble(unit, call_depth + 1)
						end
					else
						out << line
					end
				end
			elsif name == 'pipe'
				out << @eggshell.assemble(lines, call_depth + 1)
			end
		end
		
		def do_include(paths, buff, call_depth, opts = {})
			paths = [paths] if !paths.is_a?(Array)
			# @todo check all include paths?
			paths.each do |inc|
				inc = inc.line if inc.is_a?(Eggshell::Line)
				inc = @eggshell.expand_expr(inc.strip)
				checks = []
				if inc[0] != '/'
					@vars[:include_paths].each do |root|
						checks << "#{root}/#{inc}"
					end
					# @todo if :include_root, expand path and check that it's under the root, otherwise, sandbox
				else
					# sandboxed root include
					if @eggshell.vars[:include_root]
						checks << "#{@vars[:include_root]}#{inc}"
					else
						checks << inc
					end
				end
				checks.each do |inc|
					if File.exists?(inc)
						lines = IO.readlines(inc, $/, opts)
						@vars[:include_stack] << inc
						begin
							buff << @eggshell.process(lines, 0, call_depth + 1)
							@eggshell._debug("include: 200 #{inc}")
						rescue => ex
							@eggshell._error("include: 500 #{inc}: #{ex.message}#{ex.backtrace.join("\n\t")}")
						end
						
						@vars[:include_stack].pop
						break
					else
						@eggshell._warn("include: 404 #{inc}")
					end
				end
			end
		end
	end
	
	# Provides iteration and conditional functionality.
	class ControlLoopMacros
		include MH
		
		class WhileLoopWrapper
			def initialize(eggshell, cond)
				@eggshell = eggshell
				@cond = cond
			end

			def each(&block)
				counter = 0
				struct = Eggshell::ExpressionEvaluator.struct(@cond)

				cond = @eggshell.expr_eval(struct)
				while cond
					yield(counter)
					counter += 1
					cond = @eggshell.expr_eval(struct)
				end
			end
		end

		# pre.
		# @if("expression") {}
		# @elsif("expression") {}
		# else {}
		#
		# #! modes:
		# #! 'raw' (default): collects all generated lines as raw (unless there are sub-macros, which would just collect the output as as-is)
		# #! 'eval': evaluates each unit via Eggshell::Processor.assemble
		# #! note that interpolated expressions are expanded in raw mode
		# #
		# @for({'start': 0, 'stop': var, 'step': 1, 'items': ..., 'item': 'varname', 'counter': 'varname'}[, mode])
		def set_processor(proc, opts = nil)
			opts = {} if !opts
			@opts = opts
			@eggshell = proc
			@eggshell.add_macro_handler(self, *%w(if elsif else loop for while break next))
			@vars = @eggshell.vars
			@eggshell.vars[:loop_max_limit] = 1000

			@state = []
			# @todo set loop limits from opts or defaults
		end

		def process(name, args, lines, out, call_depth = 0)
			macname = name.to_sym
			st = @state[call_depth]
			if !@state[call_depth]
				st = {:type => macname}

				@state[call_depth] = st
				# erase nested state
				@state[call_depth+1] = nil
			end

			p0 = args[0]
			if macname == :for || macname == :loop || macname == :while
				p1 = args[1] || 'raw'

				looper = nil
				loop_is_map = false

				if macname == :while
					if p0
						looper = WhileLoopWrapper.new(@eggshell, p0)
					end
				else
					p0 ||= 'true'
					st[:iter] = p0['items'] || nil
					st[:item] = p0['item'] || 'item'
					st[:var] = p0['var']
					st[:start] = p0['start']
					st[:stop] = p0['stop']
					st[:step] = p0['step'] || 1
					st[:counter] = p0['counter'] || 'counter'

					if st[:iter].is_a?(Array)
						st[:start] = 0 if !st[:start]
						st[:stop] = st[:iter].length - 1 if !st[:stop]
						st[:step] = 1 if !st[:step]
						looper = Range.new(st[:start], st[:stop]).step(st[:step]).to_a
					elsif st[:iter].respond_to?(:each)
						looper = st[:iter]
						loop_is_map = true
					end
				end

				collector = out
				raw = p1 == 'raw'

				if looper
					counter = -1
					looper.each do |i1, i2|
						counter += 1
						break if @eggshell.vars[:loop_max_limit] == counter
						# for maps, use key as the counter
						val = nil
						if loop_is_map
							@eggshell.vars[st[:counter]] = i1
							val = i2
						else
							val = i1
							@eggshell.vars[st[:counter]] = counter
						end

						# inject value into :item -- if it's an expression, evaluate first
						@eggshell.vars[st[:item]] = val.is_a?(Array) && val[0].is_a?(Symbol) ? @eggshell.expr_eval(val) : val

						# if doing raw, pass through block lines with variable expansion. preserve object type (e.g. Line or String);
						# sub-macros will get passed collector var as output to assemble().
						# otherwise, call assemble() on all lines
						if raw
							lines.each do |unit|
								if unit.is_a?(Array)
									if unit[0] == :block
										unit[Eggshell::ParseTree::IDX_LINES].each do |line|
											nline = line
											if line.is_a?(String)
												nline = @eggshell.expand_expr(line)
											else
												# rather than expand_expr on raw, assume line.line is a subset of line.raw
												_raw = line.raw
												_line = @eggshell.expand_expr(line.line)
												_raw = _raw.gsub(line.line, _line) if _raw
												nline = line.replace(_line, _raw)
											end
											collector << nline
										end
									else
										@eggshell.assemble([unit], call_depth + 1, {:out => collector})
									end
								else
									collector << @eggshell.expand_expr(line.to_s)
								end
							end
						else
							collector << @eggshell.assemble(lines, call_depth + 1)
						end

						break if st[:break]
					end
				end
				
				# clear state
				@state[call_depth] = nil
			# elsif macname == :while
			# 	raw = args[1]
			# 	while @eggshell.expr_eval(p0)
			# 		process_lines(lines, buffer, depth + 1, raw)
			# 		break if st[:break]
			# 	end
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
						st[:cond_eval] = @eggshell.expr_eval(cond_struct)
					end
				else
					st[:cond_eval] = true
				end

				if st[:cond_eval] && !st[:cond_met]
					st[:cond_met] = true
					#process_lines(lines, buffer, depth + 1)
					@eggshell.assemble(lines, call_depth + 1, {:out => out})
				end
			elsif macname == :break
				lvl = p0 || 1
				i = call_depth - 1

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
	end
	
	include Eggshell::Bundles::Bundle
end
# A block handler handles one or more lines as a unit as long as all the lines
# conform to the block's expectations.
#
# Blocks are either identified explicitly:
#
# pre. block_name. some content
# \
# block_name({}). some content
#
# Or, through some non-alphanumeric character:
#
# pre. |table|start|inferred
# |another|row|here
#
# When a handler can handle a line, it sets an internal block type (retrieved 
# with {{current_type()}}). Subsequent lines are passed to {{continue_with()}}
# which returns `true` if the line conforms to the current type or `false` to
# close the block.
#
# The line or lines are finally passed to {{process()}} to generate the output.
#
# h2. Block Standards
#
# When explicitly calling a block and passing a parameter, always expect the first
# argument to be a hash of various attributes:
#
# pre. p({'class': '', 'id': '', 'attributes': {}}, other, arguments, ...). paragraph start
module Eggshell::BlockHandler
	include Eggshell::BaseHandler
	include Eggshell::ProcessHandler

	# Indicates that subsequent lines should be collected.
	COLLECT = :collect

	# Unlike COLLECT, which will parse out macros and keep the execution order,
	# this will collect the line raw before any macro detection takes place.
	COLLECT_RAW = :collect_raw

	# Indicates that the current line ends the block and all collected
	# lines should be processed.
	DONE = :done

	# A variant of DONE: if the current line doesn't conform to expected structure,
	# process the previous lines and indicate to processor that a new block has
	# started.
	RETRY = :retry

	def set_processor(proc, opts = nil)
		@eggshell = proc
		@eggshell.add_block_handler(self, *@block_types)
		@vars = @eggshell.vars
		@vars[:block_params] = {} if !@vars[:block_params]
	end

	# Resets state of line inspection.
	def reset
		@block_type = nil
	end

	# Returns the handler's current type.
	def current_type
		@block_type
	end

	# Sets the type based on the line given, and returns one of the following:
	#
	# - {{RETRY}}: doesn't handle this line;
	# - {{COLLECT}}: will collect lines following normal processing.
	# - {{COLLECT_RAW}}: will collect lines before macro/block checks can take place.
	# - {{DONE}}: line processed, no need to collect more lines.
	def can_handle(line)
		RETRY
	end

	# Determines if processing for the current type ends (e.g. a blank line usually
	# terminates the block).
	# @return Symbol {{RETRY}} if not handled at all; {{COLLECT}} to collect and
	# continue; {{DONE}} to collect this line but end the block.
	def continue_with(line)
		if line != nil && line != ''
			COLLECT
		else
			RETRY
		end
	end
	
	# Useful for pipeline chains in the form `block-macro*-block`. This checks if
	# the current block handler/type is equivalent to the block that's being pipelined.
	def equal?(handler, type)
		false
	end

	module Defaults
		class NoOpHandler
			include Eggshell::BlockHandler
		end
	end

	# Block parameters are default parameters given to a block type (e.g. setting a class).
	# The parameters should be a map. Any keys are allowed, but for HTML, the standard keys
	# that blocks will generally use are:
	#
	# - {{CLASS}}: string
	# - {{ID}}: string
	# - {{STYLE}}: string or map of styles.
	# - {{ATTRIBUTES}}: map of extra tag attributes.
	# 
	# This module has pre-filled methods to make it is to drop in the functionality
	# wherever it's needed. The assumption is that {{@vars}} is a hash.
	module BlockParams
		CLASS = 'class'
		ID = 'id'
		STYLE = 'style'
		ATTRIBUTES = 'attributes'
		KEYS = [CLASS, ID, STYLE, ATTRIBUTES].freeze

		# Sets the default parameters for a block type.
		def set_block_params(name, params)
			params = {} if !params.is_a?(Hash)
			@vars[:block_params][name] = params
		end

		# Gets the block params for a block type, merging in any defaults
		# with the passed in parameters.
		# 
		# For the key {{ATTRIBUTES}}, individual keys within that are 
		# compared to the default param's {{ATTRIBUTES}}.
		def get_block_params(name, params = {})
			params = {} if !params.is_a?(Hash)
			bparams = @vars[:block_params][name]
			if bparams
				bparams.each do |key, val|
					if key == ATTRIBUTES
						if !params[key].is_a?(Hash)
							params[key] = val
						else
							val.each do |akey, aval|
								if !params[key].has_key?(akey)
									params[key][akey] = aval
								end
							end
						end
					elsif !params.has_key?(key)
						params[key] = val
					end
				end
			end
			params
		end
	end

	# Useful methods for generating HTML tags
	module HtmlUtils
		def create_tag(tag, attribs, open = true, body = nil)
			str_attribs = ''
			if attribs.is_a?(String)
				str_attribs = attribs
			else
				nattribs = attribs.is_a?(Hash) ? attribs.clone : {}
				if nattribs[BlockParams::STYLE].is_a?(Hash)
					nattribs[BlockParams::STYLE] = css_string(nattribs[BlockParams::STYLE])
				end
				str_attribs = attrib_string(nattribs, BlockParams::KEYS)
			end

			if !open
				return "<#{tag}#{str_attribs}/>"
			else
				if body
					return "<#{tag}#{str_attribs}>#{body}</#{tag}>"
				else
					return "<#{tag}#{str_attribs}>"
				end
			end
		end

		def attrib_string(map, keys = nil)
			keys = map.keys if !keys
			buff = []
			keys.each do |key|
				val = map[key]
				if val.is_a?(Hash)
					buff << attrib_string(val)
				elsif val && key[0] != '@'
					buff << " #{key}='#{html_escape(val)}'"
				end
			end
			buff.join()
		end

		def css_string(map)
			css = []
			map.each do |s,v|
				css << "#{s}: #{html_escape(v)};"
			end
			css.join(' ')
		end

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
	end	
end
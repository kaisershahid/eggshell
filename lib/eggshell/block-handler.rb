module Eggshell::BlockHandler
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

	def set_processor(proc)
	end
	
	def set_block_params(name)
		@block_params = {} if !@block_params
		@block_params[name] = @proc.get_block_params(name)
	end
	
	def create_tag(tag, attribs, open = true)
		# @todo escape val?
		abuff = []
		attribs.each do |key,val|
			if val == nil
				abuff << key
			else
				abuff << "#{key}='#{val}'"
			end
		end
		"<#{tag} #{abuff.join(' ')}#{open ? '>' : '/>'}"
	end

	def start(name, line, buffer, indents = '', indent_level = 0)
	end

	def collect(line, buffer, indents = '', indent_level = 0)
	end

	module Defaults
		class NoOpHandler
			include Eggshell::BlockHandler
		end
	end
end
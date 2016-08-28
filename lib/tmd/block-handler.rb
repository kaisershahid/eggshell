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
	end
end
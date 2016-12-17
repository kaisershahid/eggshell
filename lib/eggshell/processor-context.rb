# Holds things like variables, line/char count, and other useful information for a {{Processor}} instance.
class Eggshell::ProcessorContext
	def initialize
		@vars = {:references => {}, :toc => [], :include_paths => [], 'log.level' => '1'}
		@funcs = {}
		@macros = {}
		@blocks = {}
		@block_params = {}
		@expr_cache = {}

		# keeps track of line counters based on include
		@lcounters = [Eggshell::LineCounter.new]
	end
	
	attr_reader :vars, :funcs, :macros, :blocks, :block_params, :expr_cache
	
	def push_line_counter
		@lcounters << Eggshell::LineCounter.new
	end
	
	def pop_line_counter
		@lcounters.pop
	end
	
	def line_counter
		@lcounters[-1]
	end
end
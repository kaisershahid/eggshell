# Holds things like variables, line/char count, and other useful information for a {{Processor}} instance.
class Eggshell::ProcessorContext
	def initialize
		@vars = {:references => {}, :toc => [], :include_paths => [], 'log.level' => 1}
		@funcs = {}
		@macros = {}
		@blocks = []
		@blocks_map = {}
		@block_params = {}
		@expr_cache = {}
		@fmt_handlers = {}
	end
	
	attr_reader :vars, :funcs, :macros, :blocks, :blocks_map, :block_params, :expr_cache, :fmt_handlers
end
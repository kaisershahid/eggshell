# Holds things like variables, line/char count, and other useful information for a {{Processor}} instance.
class Eggshell::ProcessorContext
	def initialize
		@vars = VarTable.new({:references => {}, :toc => [], :include_paths => [], 'log.level' => 1})
		@funcs = {}
		@macros = {}
		@blocks = []
		@blocks_map = {}
		@block_params = {}
		@expr_cache = {}
		@fmt_handlers = {}
	end
	
	attr_reader :vars, :funcs, :macros, :blocks, :blocks_map, :block_params, :expr_cache, :fmt_handlers
	
	# Hash-like object that allows for scoped lookup.
	class VarTable
		def initialize(vtable = {})
			@tables = []
			@tables << (vtable.is_a?(Hash) ? vtable : {})
		end
		
		def [](key)
			m = @tables.length - 1
			while m >= 0
				if @tables[m].has_key?(key)
					return @tables[m][key]
				else
					m -= 1
				end
			end
			
			return nil
		end
		
		# Sets the key for a given value.
		#
		# @param Integer level How many levels up to set this variable. Default is to keep at
		# current scope.
		def []=(key, val, level = 0)
			m = @tables.length - 1 - level
			m = 0 if m < 0
			@tables[m][key] = val
		end
		
		def has_key?(key)
			m = @tables.length - 1
			while m >= 0
				return true if @tables[m].has_key?(key)
				m -= 1
			end
			
			return false
		end

		def delete(key, level = 0)
			m = @tables.length - 1 - level
			m = 0 if m < 0
			@tables[m].delete(key)
		end
		
		def depth
			@tables.length
		end
		
		# Pushes a new state onto the stack.
		def push(vtable = nil)
			@tables << (vtable.is_a?(Hash) ? vtable : {})
		end
		
		def pop
			if @tables.length > 1
				@tables.pop
			else
				nil
			end
		end
	end
end
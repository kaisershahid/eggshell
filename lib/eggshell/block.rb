# For multiline macros, the block collects lines specific to the block (including other nested macros).
# This allows for proper execution when dealing with loops and branches.
class Eggshell::Block
	def initialize(macro, handler, args, depth, delim = nil)
		@stack = [self]
		@lines = []
		@macro = macro
		@handler = handler
		@args = args
		@delim = delim

		# reverse, and swap out
		if @delim && @delim[0] == '{'
			@delim = @delim.reverse.gsub(/\{/, '}').gsub(/\[/, ']')
		else
			@delim = nil
		end

		@depth = depth
	end

	attr_reader :depth, :lines, :delim

	# Returns the current active block.
	def cur
		@stack[-1]
	end

	# Adds a nested block to collect lines into.
	def push(block)
		@stack[-1].lines << block
		@stack << block
	end

	# Removes a nested block.
	def pop()
		@stack.pop
	end

	def collect(entry)
		@stack[-1].lines << entry
	end

	def process(buffer, depth = nil)
		@handler.process(buffer, @macro, @args, @lines, depth == nil ? @depth : depth)
	end

	def inspect
		"<BLOCK #{@macro} (#{@depth}) #{@handler.class} | #{@lines.inspect} >"
	end
end
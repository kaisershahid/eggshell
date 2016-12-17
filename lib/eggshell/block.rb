# For complex nested content, use the block to execute content correctly.
# Quick examples: nested loops, conditional statements.
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

	def cur
		@stack[-1]
	end

	def push(block)
		@stack[-1].lines << block
		@stack << block
	end

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
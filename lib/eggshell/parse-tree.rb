# Holds a hierarchical collection of blocks and macros. The tree follows
# this structure:
#
# pre. [
# String*,
# [:block, 'block_name', [], line_start]* # last entry is array of Eggshell::Line,
# [:macro, 'macro_name', {}, [
# 		__repeat_of_parse_tree
# 		]
# 	], line_start*
# ]
class Eggshell::ParseTree
	BH = Eggshell::BlockHandler

	IDX_TYPE = 0
	IDX_NAME = 1
	IDX_ARGS = 2
	IDX_LINES = 3
	IDX_LINES_START = 4
	IDX_LINES_END = 5

	def initialize
		#@eggshell = eggshell
		@modes = [:nil]
		@tree = []
		@lines = []
		@macro_delims = []
		@macro_open = []
		@macro_ptr = []
		@ptr = @tree
	end
	
	def new_macro(line_obj, line_start)
		line = line_obj.line
		macro, args, delim = Eggshell::Processor.parse_macro_start(line)

		push_block

		if delim
			@modes << :macro
			@macro_delims << delim.reverse.gsub('[', ']').gsub('(', ')').gsub('{', '}')
			@macro_open << line
			@macro_ptr << @ptr
			# set ptr to entry's tree
			entry = [:macro, macro, args, [], line_start]
			@ptr << entry
			@ptr = entry[IDX_LINES]
		else
			@ptr << [:macro, macro, args, [], line_start]
		end
	end
	
	def macro_delim_match(line_obj, line_num)
		if @macro_delims[-1] == line_obj.line
			if @modes[-1] == :block
				push_block
			end
			@macro_delims.pop
			@macro_open.pop
			@ptr = @macro_ptr.pop
			@ptr[-1] << line_num
			last_mode = @modes.pop
			return true
		end
		return false
	end

	def new_block(handler, type, line_obj, consume_mode, line_start)
		block_type, args, line = Eggshell::Processor.parse_block_start(line_obj.line)
		nline = Eggshell::Line.new(line, line_obj.tab_str, line_obj.indent_lvl, line_obj.line_num)

		if consume_mode != BH::DONE
			@modes << :block
			if line != ''
				@lines << nline
				line_start -= 1
			end
			@cur_block = [handler, type, args, line_start]
			if consume_mode == BH::COLLECT_RAW
				mode = :raw
			else consume_mode == BH::COLLECT
				mode = :block
			end
		else
			@ptr << [:block, type, args, [nline], line_start]
		end
	end

	def push_block
		if @modes[-1] == :block
			if @cur_block
				line_end = @cur_block[3]
				line_end = @lines[-1].line_num if @lines[-1]
				@ptr << [:block, @cur_block[1], @cur_block[2], @lines, @cur_block[3], line_end]
				@lines = []
				@cur_block[0].reset
				@cur_block = nil
			end
			@modes.pop
		end
	end

	def collect(line_obj)
		more = @cur_block[0].continue_with(line_obj.line)
		if more != BH::RETRY
			@lines << line_obj
			if more == BH::DONE
				push_block
			end
		else
			push_block
		end
		more
	end
	
	def raw_line(line_obj)
		@ptr << line_obj
	end
	
	def tree
		@tree.clone
	end
	
	# @todo return macro_open
	
	def mode
		@modes[-1]
	end
	
	# Does basic output of parse tree structure to visually inspect parsed info.
	def self.walk(struct = nil, indent = 0, out = nil)
		out = $stdout if !out
		struct.each do |row|
			if row.is_a?(Eggshell::Line)
				out.write "#{'  '*indent}#{row.to_s.inspect} ##{row.line_num}\n"
			elsif row.is_a?(Array)
				if row[0] == :macro
					out.write "#{'  '*indent}@#{row[1]}(#{row[2].inspect}) | end=#{row[-1]}\n"
					walk(row[3], indent + 1, out)
				elsif row[0] == :block
					out.write "#{'  '*indent}#{row[1]}(#{row[2].inspect}) | end=#{row[-1]}\n"
					walk(row[3], indent + 1, out)
				end
			else
				out.write "#{'  '*indent}#{row.inspect} ?\n"
			end
		end
	end
end
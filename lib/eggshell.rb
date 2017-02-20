# Eggshell.
module Eggshell
	VERSION_MAJOR = 1
	VERSION_MINOR = 0
	VERSION_PATCH = 2
	VERSION = "#{VERSION_MAJOR}.#{VERSION_MINOR}.#{VERSION_PATCH}"
	# Encapsulates core parts of a line. Handler can use whatever parts are needed to 
	# construct final output. Line number is provided for error reporting.
	class Line
		def initialize(line, tab_str, indent_lvl, line_num, raw = nil)
			@line = line
			@tab_str = tab_str || ''
			@indent_lvl = indent_lvl
			@line_num = line_num
			@raw = raw
		end
		
		# Returns the raw line with indents.
		def to_s
			"#{@tab_str*@indent_lvl}#{@line}"
		end
		
		def raw
			@raw ? @raw : to_s
		end

		# Creates a new instance of this line, replacing the actual contents with the supplied line.
		def replace(line, raw = nil)
			Line.new(line, @tab_str, @indent_lvl, @line_num, raw)
		end
		
		attr_reader :line, :tab_str, :indent_lvl, :line_num
	end

	# Core interface for plugins.	
	module BaseHandler
		# Lets the handler attach itself to the processor instance.
		# @param Eggshell::Processor proc
		# @param Hash opts Optional parameters. Potential use cases might include only handling
		# a subset of possible actions. Think of this as a way to sandbox behavior.
		def set_processor(proc, opts = nil)
			@eggshell = proc
		end
	end
	
	# Core interface for processing content plugins.
	# @param String type The name of the action to take (note that a handler can support multiple functions).
	# @param Array args The arguments supplied to the handler within the content (e.g. `p(arg1,arg2,...). text`)
	# @param Array lines A collection of {@see Line}, {{Handler}}, and {{String}} objects to convert. This may
	# also include nested document sections.
	# @param Object out The output object to write data to. Must support {{<<}} and {{join(String)}} methods.
	# @param Integer call_depth The nesting level of the current call.
	module ProcessHandler
		def process(type, args, lines, out, call_depth = 0)
		end
	end
end

require_relative './eggshell/expression-evaluator.rb'
require_relative './eggshell/format-handler.rb'
require_relative './eggshell/block-handler.rb'
require_relative './eggshell/macro-handler.rb'
require_relative './eggshell/processor-context.rb'
require_relative './eggshell/parse-tree.rb'
require_relative './eggshell/processor.rb'
require_relative './eggshell/bundles.rb'
# Interface for handling inline formatting. Markup follows this general structure:
# {{open_delim + string + close_delim}}. Opening and closing delimiters are defined
# by the handler.
module Eggshell::FormatHandler
	def set_processor(proc, opts = nil)
		@eggopts = opts || {}
		@eggshell = proc
		@eggshell.add_format_handler(self, @fmt_delimeters)
		if self.respond_to?(:post_processor)
			post_processor
		end
	end

	# @param String|MatchData tag The opening delimeter.
	# @param String str The string between delimeters.
	def format(tag, str)
	end
	
	module Utils
		# Parses arguments in the form: `arg0 ; arg1 ; ...|att=val|att2=val|...`
		#
		# The first portion is the direct argument. For instance, a link like 
		# `[~ link ; text ~]` or an image like `[! src ; alt !]`. The remaining
		# piped args are key-value pairs (use `\\|` to escape) which might
		# be embedded in the tag or signal some further transformations.
		#
		# If any contexts don't use direct arguments, set {{no_direct}} to `true`.
		# This will produce a 1-element array with a map.
		#
		# @param String arg_str A pipe-separated argument list, with first argument
		# interpreted as a direct arguments list.
		# @param Boolean no_direct If true, doesn't treat first argument as direct
		# arguments.
		# @return An array where the last element is always a {{Hash}}
		def parse_args(arg_str, no_direct = false)
			return [] if !arg_str || arg_str == ''
			raw_args = arg_str.split(/(?<!\\)\|/)
			args = []
			args += raw_args.shift.split(/ ; /) if !no_direct
			map = {}
			raw_args.each do |rarg|
				k, v = rarg.split('=', 2)
				map[k] = v
			end
			args << map
			args
		end
	end
end
# Macros are extensible functions that can do a lot of things:
# 
# - include other TMD documents into current document
# - process part of a document into a variable
# - do conditional processing
# - do loop processing
# - etc.
#
# A typical macro call looks like this: `@macro(param, param, ...)` and 
# must be the first item on the line (excluding whitespace).
#
# If a macro encloses a chunk of document, it would generally look like
# this:
#
# pre. @block_macro(param, ...)
# misc content
# misc content
# @end_block_macro
#
# 
module TMD::MacroHandler
	def set_processor(proc)
	end

	def process(buffer, macname, args, lines, indent)
	end

	module Defaults
		class NoOpHandler
			include TMD::MacroHandler

			def set_processor(proc)
				@proc = proc
			end

			def process(buffer, macname, args, lines, indent)
				@proc._warn("couldn't find macro: #{macname}")
			end
		end	
	end
end
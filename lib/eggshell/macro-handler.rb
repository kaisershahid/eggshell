# Macros are extensible functions that can do a lot of things:
# 
# - include other Eggshell documents into current document
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
module Eggshell::MacroHandler
	include Eggshell::BaseHandler
	include Eggshell::ProcessHandler

	
	COLLECT_NORMAL = :collect_normal
	COLLECT_RAW_MACRO = :collect_raw_macro
	COLLECT_RAW = :collect_raw

	# Indicates how to process lines contained with in the macro. {{COLLECT_NORMAL}}
	# continues to evaluate block and macro content. {{COLLECT_RAW_MACRO}} collects
	# all lines as raw unless a macro is encountered. {{COLLECT_RAW}} collects all
	# lines as raw, regardless of nested macros.
	# @todo needed?
	def collection_type(macro)
		COLLECT_NORMAL
	end

	module Defaults
		class NoOpHandler
			include Eggshell::MacroHandler

			def process(name, args, lines, out, call_depth = 0)
				@eggshell._warn("not implemented: #{macname}")
			end
		end	
	end
end
# Standard functions to perform basic operations for common objects.
module Eggshell::Bundles::BasicFunctions
	def self.length(obj)
		if obj.respond_to?(:length)
			obj.length
		else
			nil
		end
	end

	def self.str_match(haystack, needle)
	end

	def self.str_split(str, delim, limit = nil)
	end

	def self.arr_push(arr, *items)
	end
	
	def self.arr_pop(arr)
	end
	
	def self.arr_delete(arr, index)
	end

	def self.map_push(map, key, val)
	end

	def self.map_delete(map, key)
	end
end
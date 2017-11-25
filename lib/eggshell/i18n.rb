<<-DOC

DOC
module Eggshell; module I18n
	"""
	Structure of dictionary:
	
	en:
		simple_key: 'Value'
		simple_key2: 'Value %{var}'
		# this needs at least 2 elements in array. first element is for 0 or 2+, second element is for 1. if more than
		# 2 strings are supplied, the following logic applies: 0 - 0 items; 1 - 1 item; 2 - 2+ items (if last); 3 - 3+ items (if last), etc.
		# pass the '_count' key in options
		plural_key:
			- '0 or 2+'
			- '1'
		# pass the '_scope' key in options to select the appropriate string. define the 'default' key if _scope doesn't match 
		# any of the existing entries
		complex_key:
			male: 'this string is for male gender'
			female: 'this string is for female gender'
			default: 'this string is for unknown gender %{_scope}'
	"""
	class Dictionary
		def initialize(opts = {})
			opts = opts || {}
			@fallback = 'en'
			@locale = locale || @fallback
			@dict = {}
			@dict.update(opts[:dict]) if opts[:dict].is_a?(Hash)
		end
		
		def set_fallback(fallback)
			@fallback = fallback if fallback.is_a?(String)
		end

		def set_locale(locale)
			@locale = locale
		end

		def translate(key, opts = nil, locale = nil)
			opts = {} if !opts.is_a?(Hash)
		end
		
		# def transliterate(str, locale = nil)
		# end
		
		# Returns a copy of the raw dictionary entry.
		def get_entry(key, locale = nil)
		end
		
		# @param String locale If {{nil}}, use fallback locale.
		def set_entry(key, entry, locale = nil)
			locale = @fallback if !locale
			key = key.to_s if key.is_a?(Symbol)
			key = key.split('.') if key.is_a?(String)
			@dict[locale] = {} if !@dict[locale]
			if key.length == 1
				@dict[locale][key[0]] = entry
			else
				ptr = @dict[locale]
				last_key = key.pop
				key.each do |k|
					ptr = ptr[k] || {}
				end
				ptr[last_key] = entry
			end
		end
		
		#protected
		
		# @param String locale Either a language (`en`), or a language locale (`en-us`). If a 
		# language locale is specified, the language becomes part of the fallback.
		# @param Array,String,Symbol Either a symbol, string (with '.' separating hierarchy), or an array
		# of hierarchical keys.
		def find_entry(locale, key)
			lang, loc = locale.downcase.split(/[-_]/, 2)
			lang_fb = loc == nil ? @fallback : locale
			
			# setup the fallback chain
			dicts = []
			dicts << @dict[locale] if @dict.has_key?(locale)
			dicts << @dict[lang] if @dict.has_key?(lang) && lang != locale
			dicts << @dict[lang_fb] if @dict.has_key?(lang_fb)
			dicts << @dict[@fallback] if (@fallback != lang_fb && @fallback != locale) && @dict.has_key?(@fallback)

			key = key.to_s.split('.') if key.is_a?(Symbol)
			key = key.split('.') if key.is_a?(String)
			
			ptr = nil
			dicts.each do |dict|
				puts "checking #{dict.inspect}"
				ptr = dict
				key.each do |k|
					puts "	k=#{k} | ptr=#{ptr.class}"
					ptr = ptr[k]
					break if !ptr
				end
				break if ptr
			end
			
			ptr
		end
	end
	
	module Storage
		def connect(endpoint, opts = {})
		end

		def get_dictionary()
		end

		def save!
		end
	end
end; end
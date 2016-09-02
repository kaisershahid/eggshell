# This bundle is used to interpret eggshell configs.
module Eggshell::Bundles::Loader
	BUNDLE_ID = 'loader'

	def self.new_instance(proc, opts = nil)
		LoaderMacro.new.set_processor(proc)
	end

	def self.class_from_string(str)
		str.split('::').inject(Object) do |mod, class_name|
			mod.const_get(class_name)
		end
	end

	class LoaderMacro
		def set_processor(proc)
			@proc = proc
			proc.register_macro(self, *%w(gems files bundles vars))
		end

		def process(buffer, macname, args, lines, depth)
			if macname == 'gems'
				args.each do |gemname|
					begin
						require gemname
					rescue LoadError
						@proc._warn("could not load gem: #{gemname}")
					end
				end
			elsif macname == 'files'
				args.each do |file|
					begin
						require file
					rescue LoadError
						@proc._warn("could not load file: #{file}")
					end
				end
			elsif macname == 'bundles'
				args.each do |bundle|
					Eggshell::Bundles::Registry.attach_bundle(bundle, @proc.vars[:target])
				end
			end
		end
	end

	include Eggshell::Bundles::Bundle
end
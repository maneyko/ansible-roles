Gem.post_install do |installer|
  roots = [installer.gem_dir, installer.spec.extension_dir]
  paths = roots.flat_map {|root| Dir.glob("#{root}/**/*", File::FNM_DOTMATCH) }
  paths.concat [installer.spec_file, installer.spec.cache_file]

  paths.each do |path|
    next if File.symlink?(path) || !File.exist?(path)
    mode = File.stat(path).mode & 0o7777
    File.chmod(mode | (File.directory?(path) ? 0o2070 : 0o060), path)
  end
end

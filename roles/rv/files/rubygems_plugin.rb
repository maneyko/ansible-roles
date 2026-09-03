Gem.post_install do |installer|
  [installer.gem_dir, installer.spec.extension_dir].each do |root|
    Dir.glob("#{root}/**/*", File::FNM_DOTMATCH) do |path|
      next if File.symlink?(path)
      mode = File.stat(path).mode & 0o7777
      File.chmod(mode | (File.directory?(path) ? 0o2070 : 0o060), path)
    end
  end
end

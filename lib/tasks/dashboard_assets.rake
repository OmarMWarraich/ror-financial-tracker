namespace :dashboard do
  task :build do
    raise "Dashboard React asset build failed" unless system("npm", "run", "build:dashboard")
  end
end

Rake::Task["tailwindcss:build"].enhance(["dashboard:build"])
Rake::Task["assets:precompile"].enhance(["dashboard:build"])

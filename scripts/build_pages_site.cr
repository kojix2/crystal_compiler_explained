#!/usr/bin/env crystal

require "file_utils"
require "ecr"

SCRIPT_DIR = {{ __DIR__ }}
REPO_ROOT = File.expand_path("..", SCRIPT_DIR)

CRYSTAL_REF = ENV["CRYSTAL_REF"]? || "master"
CRYSTAL_ARCHIVE_URL = "https://github.com/crystal-lang/crystal/archive/refs/heads/#{CRYSTAL_REF}.tar.gz"

CRYSTAL_ARCHIVE = File.join(REPO_ROOT, "crystal-master.tar.gz")
CRYSTAL_SRC_DIR = File.join(REPO_ROOT, "crystal-master")
SITE_DIR = File.join(REPO_ROOT, "site")
COMPILER_DOCS_DIR = File.join(CRYSTAL_SRC_DIR, "docs")

DOC_FILES = ["README.md", "JA.md", "EN.md"] of String
REQUIRED_TOOLS = ["wget", "tar", "make", "cp"] of String

def log(message : String)
  puts "[docs] #{message}"
end

def fail!(message : String) : NoReturn
  STDERR.puts "[docs] ERROR: #{message}"
  exit 1
end

def run_cmd(cmd : String, args : Array(String), chdir : String? = nil)
  status = Process.run(cmd, args, chdir: chdir, output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
  return if status.success?
  fail!("Command failed (#{status.exit_code}): #{cmd} #{args.join(" ")}")
end

def command_exists?(name : String) : Bool
  status = Process.run("which", [name], output: Process::Redirect::Close, error: Process::Redirect::Close)
  status.success?
end

def require_tools
  REQUIRED_TOOLS.each do |tool|
    fail!("Required command not found: #{tool}") unless command_exists?(tool)
  end
end

def require_files
  DOC_FILES.each do |rel_path|
    abs_path = File.join(REPO_ROOT, rel_path)
    fail!("Required file not found: #{abs_path}") unless File.file?(abs_path)
  end

  [
    File.join(SCRIPT_DIR, "templates", "index.html.ecr"),
    File.join(SCRIPT_DIR, "templates", "doc_page.html.ecr"),
  ].each do |template|
    fail!("Required template not found: #{template}") unless File.file?(template)
  end
end

def download_crystal_source
  log "Downloading Crystal source (#{CRYSTAL_REF})"
  FileUtils.rm_rf(CRYSTAL_SRC_DIR)
  File.delete(CRYSTAL_ARCHIVE) if File.exists?(CRYSTAL_ARCHIVE)

  run_cmd("wget", ["-O", CRYSTAL_ARCHIVE, CRYSTAL_ARCHIVE_URL])
  run_cmd("tar", ["xvf", CRYSTAL_ARCHIVE, "-C", REPO_ROOT])
end

def build_compiler_docs
  log "Generating compiler docs"
  run_cmd("make", ["docs", "DOCS_OPTIONS=src/compiler/crystal.cr"], chdir: CRYSTAL_SRC_DIR)
end

def render_doc_page(title : String, md_file : String) : String
  ECR.render("#{__DIR__}/templates/doc_page.html.ecr")
end

def render_index_page : String
  ECR.render("#{__DIR__}/templates/index.html.ecr")
end

def assemble_site
  log "Assembling static Pages output"

  FileUtils.rm_rf(SITE_DIR)
  FileUtils.mkdir_p(File.join(SITE_DIR, "compiler"))

  DOC_FILES.each do |rel_path|
    FileUtils.cp(File.join(REPO_ROOT, rel_path), File.join(SITE_DIR, rel_path))
  end

  run_cmd("cp", ["-R", "#{COMPILER_DOCS_DIR}/.", File.join(SITE_DIR, "compiler")])
  File.write(File.join(SITE_DIR, "index.html"), render_index_page)
  File.write(File.join(SITE_DIR, "ja.html"), render_doc_page("Crystal Compiler Explained (JA)", "JA.md"))
  File.write(File.join(SITE_DIR, "en.html"), render_doc_page("Crystal Compiler Explained (EN)", "EN.md"))
  File.write(File.join(SITE_DIR, ".nojekyll"), "")
end

def main
  Dir.cd(REPO_ROOT) do
    require_tools
    require_files
    download_crystal_source
    build_compiler_docs
    assemble_site
    log "Built static Pages artifact in #{SITE_DIR}"
  end
end

main

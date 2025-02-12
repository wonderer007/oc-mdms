#!/usr/bin/env ruby

require 'open3'
require 'pathname'
require 'optparse'

# Check if GitHub CLI (gh) is installed
def gh_installed?
  system('which gh > /dev/null 2>&1')
end

# Check if user is authenticated with GitHub CLI
def gh_authenticated?
  _, _, status = Open3.capture3('gh auth status')
  status.success?
end

# Extract JIRA ticket number from branch name
def extract_jira_ticket(branch_name)
  match = branch_name.match(/\b[A-Z]{2,3}-\d+\b/i)
  match ? match[0].upcase : nil
end

# Generate a formatted PR title
def format_pr_title(branch_name, jira_ticket, repo_label, branch_label)
  branch_regex = %r{^([a-zA-Z]*\/)?[a-zA-Z]{2,3}-[0-9]+}
  branch_prefix = branch_name.match(branch_regex)&.[](0)
  ticket_title = branch_name[branch_prefix.length..].gsub(/[-_]/, ' ').split.map(&:capitalize).join(' ')
  "[#{branch_label}, #{repo_label}] #{jira_ticket}: #{ticket_title}"
end

# Create a pull request
def create_pull_request(branch_name, base_branch, pr_title, pr_description)
  stdout, stderr, status = Open3.capture3(
    'gh', 'pr', 'create', '--title', pr_title,
    '--body', pr_description,
    '--head', branch_name,
    '--base', base_branch,
    '--assignee', '@me'
  )

  if status.success?
    puts "✅ Pull request created for #{base_branch}!"
    stdout.strip
  else
    existing_url = stderr.match(/already exists:\s*(https:\/\/.*?)(?:\s|$)/)&.[](1)
    if existing_url
      puts "⚠️ Existing pull request found for #{base_branch}!"
    else
      puts "❌ Error creating PR for #{base_branch}: #{stderr}"
    end

    existing_url
  end
end

# Update PR descriptions with cross-links
def update_pr_descriptions(pr_map, jira_link)
  pr_map.each do |base_branch, pr_url|
    next unless pr_url

    linked_prs = pr_map.reject { |b, _| b == base_branch }
                       .map { |b, url| "PR against `#{b}`: #{url}" }
                       .join("\n")

    new_description = <<~DESC
      JIRA: #{jira_link}

      #{linked_prs}

      ## Describe your changes
    DESC

    Open3.capture3('gh', 'pr', 'edit', pr_url, '--body', new_description)
    puts "🔄 Updated description for PR against #{base_branch}"
  end
end

# Parse command line arguments
def parse_arguments
  options = {
    skip_main: false,
    skip_devel: false,
    skip_stage: false
  }

  OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options]"
    opts.on('--no-main', 'Skip creating PR for main branch') { options[:skip_main] = true }
    opts.on('--no-ci-devel-server', 'Skip creating PR for ci-devel-server branch') { options[:skip_devel] = true }
    opts.on('--no-ci-stage-server', 'Skip creating PR for ci-stage-server branch') { options[:skip_stage] = true }
  end.parse!

  options
end

# Main execution starts here
abort '❌ Error: GitHub CLI (gh) is not installed. Install it from https://cli.github.com/' unless gh_installed?
abort '❌ Error: Not authenticated with GitHub CLI. Run `gh auth login`.' unless gh_authenticated?

options = parse_arguments
branch_name = `git symbolic-ref --short HEAD`.strip
jira_ticket = extract_jira_ticket(branch_name)
abort '❌ Error: Cannot find JIRA ticket number in branch name!' unless jira_ticket

repo_name = Pathname.pwd.basename.to_s
all_target_branches = %w[main ci-devel-server ci-stage-server]
target_branches = all_target_branches.reject do |branch|
  case branch
  when 'main' then options[:skip_main]
  when 'ci-devel-server' then options[:skip_devel]
  when 'ci-stage-server' then options[:skip_stage]
  end
end

abort '❌ Error: No target branches selected for PR creation!' if target_branches.empty?

BRANCH_LABELS = {
  'main' => 'main',
  'ci-devel-server' => 'dev',
  'ci-stage-server' => 'stage'
}.freeze

REPO_LABELS = {
  'mdms' => 'mdms',
  'ums' => 'ums',
  'owenscorning.com-global' => 'global'
}.freeze

repo_label = REPO_LABELS.fetch(repo_name, repo_name)
jira_link = "https://owenscorning.atlassian.net/browse/#{jira_ticket}"
pr_map = {}

# Create PRs for each target branch
target_branches.each do |base_branch|
  branch_label = BRANCH_LABELS.fetch(base_branch, base_branch)
  pr_title = format_pr_title(branch_name, jira_ticket, repo_label, branch_label)
  pr_description = "JIRA: #{jira_link}\n\n## Describe your changes"

  pr_map[base_branch] = create_pull_request(branch_name, base_branch, pr_title, pr_description)
end

# Update PR descriptions with cross-links
update_pr_descriptions(pr_map, jira_link) if pr_map.values.any?

puts '🎉 All pull requests created and linked successfully!'

#!/usr/bin/env ruby

require 'open3'
require 'pathname'

def gh_installed?
  system('which gh > /dev/null 2>&1')
end

def gh_authenticated?
  _, _, status = Open3.capture3('gh auth status')
  status.success?
end

unless gh_installed?
  puts 'Error: GitHub CLI (gh) is not installed.'
  puts 'Please install it from: https://cli.github.com/'
  exit 1
end

unless gh_authenticated?
  puts 'Error: Not authenticated with GitHub CLI.'
  puts 'Please run: gh auth login'
  exit 1
end

branch_name = `git symbolic-ref --short HEAD`.strip
branch_regex = %r{^([a-zA-Z]*\/)?[a-zA-Z]{2,3}-[0-9]+}
branch_prefix = branch_name.match(branch_regex)&.[](0)
jira_ticket = branch_name.match(%r{(?i)[a-zA-Z]{2,3}-[0-9]+})&.[](0)
repo_name = Pathname.pwd.basename.to_s
target_branches = %w[main ci-devel-server ci-stage-server]

BRANCH_LABELS = {
  'main': 'main',
  'ci-devel-server': 'dev',
  'ci-stage-server': 'stage'
}.freeze

REPO_LABELS = {
  'mdms': 'mdms',
  'ums': 'ums',
  'owenscorning.com-global': 'global'
}.freeze

if jira_ticket
  ticket_title = branch_name[branch_prefix.length..].gsub(/[-_]/, ' ').split.map(&:capitalize).join(' ')
  jira_link = "https://owenscorning.atlassian.net/browse/#{jira_ticket}"
  repo_label = REPO_LABELS[repo_name.to_sym] || repo_name

  pr_map = {}
  target_branches.each do |base_branch|
    branch_label = BRANCH_LABELS[base_branch.to_sym]
    pr_title = "[#{branch_label}, #{repo_label}] #{jira_ticket}: #{ticket_title}"
    pr_description = <<~DESC
      JIRA: #{jira_link}

      ## Describe your changes
    DESC

    stdout, stderr, status = Open3.capture3(
      'gh', 'pr', 'create', '--title', pr_title,
      '--body', pr_description,
      '--head', branch_name,
      '--base', base_branch,
      '--assignee', '@me'
    )

    pr_url = if status.success?
               stdout.strip
               puts "Pull request created for #{base_branch}!"
             else
               existing_url = stderr.match(/already exists:\s*(https:\/\/.*?)(?:\s|$)/)&.[](1)
               puts "Existing pull request found for #{base_branch}!" if existing_url
               existing_url
             end

    pr_map[base_branch] = pr_url if pr_url
  end

  pr_map.each do |base_branch, pr_url|
    new_description = <<~DESC
      JIRA: #{jira_link}

      #{pr_map.map do |other_branch, other_url|
        next if other_branch == base_branch

        "PR against `#{other_branch}`: #{other_url}"
      end.compact.join("\n")}

      ## Describe your changes
    DESC

    Open3.capture3(
      'gh', 'pr', 'edit', pr_url,
      '--body', new_description
    )
    puts "Updated description for PR against #{base_branch}"
  end

  puts 'All pull requests created and updated successfully!'
else
  puts 'Can not find JIRA ticket number'
end

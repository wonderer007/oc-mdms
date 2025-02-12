#!/usr/bin/env ruby

require 'open3'
require 'pathname'

branch_name = `git symbolic-ref --short HEAD`.strip
branch_regex = /^([a-zA-Z]*\/)?[a-zA-Z]{2,3}-[0-9]+/
branch_prefix = branch_name.match(branch_regex)&.[](0)
jira_ticket = branch_name.match(/(?i)[a-zA-Z]{2,3}-[0-9]+/)&.[](0)
repo_name = Pathname.pwd.basename.to_s
target_branches = ["main", "ci-devel-server", "ci-stage-server"]

BRANCH_LABELS = {
  "main" => "main",
  "ci-devel-server" => "dev",
  "ci-stage-server" => "stage"
}

if jira_ticket
  ticket_title = branch_name[branch_prefix.length..]
    .gsub(/[-_]/, ' ')
    .split
    .map(&:capitalize)
    .join(' ')

  commit_message = `git log -1 --pretty=%B`.strip
  jira_link = "https://owenscorning.atlassian.net/browse/#{jira_ticket}"

  pr_map = {}
  # Create PRs for each target branch
  target_branches.each do |base_branch|
    pr_title = "[#{BRANCH_LABELS[base_branch]}, #{repo_name}] #{jira_ticket}: #{ticket_title}"
    pr_description = <<~DESC
      JIRA: #{jira_link}

      ## Describe your changes
      #{commit_message}
    DESC

    stdout, stderr, status = Open3.capture3("gh", "pr", "create", "--title", pr_title, "--body", pr_description, "--head", branch_name, "--base", base_branch, "--assignee", "@me")

    pr_url = if status.success?
      stdout.strip
    else
      stderr.match(/already exists:\s*(https:\/\/.*?)(?:\s|$)/)&.[](1)
    end

    pr_map[base_branch] = pr_url if pr_url
    puts "Pull request created/found for #{base_branch}!"
  end

  pr_map.each do |base_branch, pr_url|
    new_description = <<~DESC
      JIRA: #{jira_link}

      #{pr_map.map { |other_branch, other_url|
        next if other_branch == base_branch
        "PR against `#{other_branch}`: #{other_url}"
      }.compact.join("\n")}

      ## Describe your changes
      #{commit_message}
    DESC

    Open3.capture3("gh", "pr", "edit", pr_url, "--body", new_description)
    puts "Updated description for PR against #{base_branch}"
  end

  puts "All pull requests created and updated successfully!"
else
  puts "Can not find JIRA ticket number"
end

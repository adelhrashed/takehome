require 'json'

# The code is split into two services TopUpUserService  and GenerateTopUpReportService.
# This split allows each service to be have single resposibility. It also decouples
# the logic of topping users from generating a report.
# This allows the code to be resusable, maintainble, and testable

class TopUpUsersService
  attr_reader :companies, :users

  def initialize(companies, users)
    @companies = companies
    @users = users
  end

  def run
    users_by_company = group_users_by_company
    companies.map do |company|
      company_id = company[:id]

      if company_id.nil?
        puts "Error: Company #{company[:name]} is missing id"
        next
      end

      company_users = users_by_company[company_id]
      next if company_users.nil?

      active_users = company_users.select { |user| user[:active_status] == true }
      next if active_users.empty?

      company_top_up =
        if company[:top_up].is_a? Numeric
          company[:top_up]
        else
          puts "Warning: Company #{company_id} has invalid top_up value"
          0
        end
      company_email_status = company[:email_status] == true
      company_total_top_up = 0

      result = active_users.map do |user|
        previous_token_balance =
          if user[:tokens].is_a? Numeric
            user[:tokens]
          else
            puts "Warning: User #{user[:id]} has invalid tokens value"
            0
          end

        new_token_balance = previous_token_balance + company_top_up
        send_email = company_email_status && user[:email_status] == true
        company_total_top_up += company_top_up

        { **user,
          previous_token_balance: previous_token_balance,
          new_token_balance: new_token_balance,
          send_email: send_email }
      end

      { **company, total_top_up: company_total_top_up, users: result }
    end.compact
  end

  def group_users_by_company
    grouped_users = {}
    users.each do |user|
      company_id = user[:company_id]
      if company_id.nil?
        puts "Error: User #{user[:id]} is missing company_id"
        next
      end

      grouped_users[company_id] ||= []
      grouped_users[company_id] << user
    end
    grouped_users
  end
end

class GenerateTopUpReportService
  attr_reader :data, :file_path

  def initialize(data, file_path)
    @data = data
    @file_path = file_path
  end

  def generate_report
    formatted_data = format_data
    File.write(file_path, formatted_data)
  end

  def format_data
    data.sort_by { |company| company[:id] }.map do |company|
      format_company_data(company)
    end.join("\n")
  end

  def format_company_data(company_data)
    sorted_users = company_data[:users].sort_by { |user| user[:last_name] || '' } # in case last name is missing
    emailed_users, not_emailed_users = sorted_users.partition { |user| user[:send_email] }
    output_lines = []
    output_lines << "Company Id: #{company_data[:id]}\n"
    output_lines << "Company Name: #{company_data[:name]}\n"
    output_lines << "Users Emailed:\n"
    output_lines.concat(emailed_users.map { |user| format_user_data(user).to_s })
    output_lines << "Users Not Emailed:\n"
    output_lines.concat(not_emailed_users.map { |user| format_user_data(user).to_s })
    output_lines << "Total amount of top ups for #{company_data[:name]}: #{company_data[:total_top_up]}\n"
    output_lines.join
  end

  def format_user_data(user_data)
    "\t#{user_data[:last_name]}, #{user_data[:first_name]}, #{user_data[:email]}\n" \
    "\t\tPrevious Token Balance, #{user_data[:previous_token_balance]}\n" \
    "\t\tNew Token Balance #{user_data[:new_token_balance]}\n"
  end
end

def load_data(file_path)
  JSON.parse(File.read(file_path), symbolize_names: true)
end

def process_data(companies_file, users_file, output_file)
  companies = load_data(companies_file)
  users = load_data(users_file)

  results = TopUpUsersService.new(companies, users).run
  GenerateTopUpReportService.new(results, output_file).generate_report
end

# Run the processing function
process_data('companies.json', 'users.json', 'output.txt')

namespace :audit_item_consistency do
  def check_content_item(content_id)
    checker = ContentConsistencyChecker.new(content_id)
    errors = checker.call

    if errors.any?
      puts "#{content_id} 😱"
      puts errors
    end
    errors.none?
  end

  desc "Check content items for consistency across the router-api and content-store"
  task :check, [:content_id] => [:environment] do |t, args|
    check_content_item args[:content_id]
  end

  desc "Check many content items for ..."
  task check_many: :environment  do
    failure_count = 0

    ContentItem.distinct.pluck(:content_id).take(50).each do |content_id|
      unless check_content_item(content_id)
        failure_count += 1
      end
    end

    puts "Failure count: #{failure_count}"
  end
end

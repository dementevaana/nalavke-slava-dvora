# name: nalavke-slava-dvora
# about: Рейтинги Слава двора за скользящие 7 дней и создание улиц участниками
# version: 0.2
# authors: NaLavke
# url: https://github.com/dementevaana/nalavke-slava-dvora

after_initialize do
  register_category_custom_field_type("nl_owner_id", :integer)
  register_category_custom_field_type("nl_adult", :boolean)
  register_category_custom_field_type("nl_topic", :string)

  class ::SlavaDvoraController < ::ApplicationController
    def index
      render_json_dump(
        created_topics: top(4),
        replies: top(5),
        likes_received: top(2),
        likes_given: top(1),
      )
    end

    private

    def top(action_type)
      rows = DB.query(<<~SQL, action_type: action_type)
        SELECT u.username, u.uploaded_avatar_id, COUNT(*) AS cnt
        FROM user_actions ua
        JOIN users u ON u.id = ua.user_id
        JOIN topics t ON t.id = ua.target_topic_id
        JOIN categories c ON c.id = t.category_id
        WHERE ua.action_type = :action_type
          AND ua.created_at > now() - interval '7 days'
          AND u.id > 0
          AND t.deleted_at IS NULL
          AND t.archetype = 'regular'
          AND NOT c.read_restricted
        GROUP BY u.id
        ORDER BY cnt DESC, u.username
        LIMIT 5
      SQL

      rows.map do |r|
        {
          username: r.username,
          count: r.cnt,
          avatar_template: User.avatar_template(r.username, r.uploaded_avatar_id),
        }
      end
    end
  end

  class ::NalavkeStreetsController < ::ApplicationController
    before_action :ensure_logged_in

    MIN_TRUST_LEVEL = 1

    def create
      if current_user.trust_level < MIN_TRUST_LEVEL && !current_user.staff?
        return render_json_error("Улицы можно создавать после первых шагов на сайте.", status: 403)
      end

      name = params[:name].to_s.strip
      description = params[:description].to_s.strip
      topic = params[:topic].to_s.strip

      unless params[:agree].to_s == "true"
        return render_json_error("Нужно согласиться с правилами.", status: 422)
      end
      unless name.length.between?(3, 40)
        return render_json_error("Название улицы: от 3 до 40 символов.", status: 422)
      end
      if description.length > 300
        return render_json_error("Описание: не больше 300 символов.", status: 422)
      end

      RateLimiter.new(current_user, "nl-create-street", 1, 1.day).performed! unless current_user.staff?

      attrs = { name: name, permissions: { "everyone" => 1 } }
      attrs[:description] = description if description.present?

      category = CategoryCreator.create(Guardian.new(Discourse.system_user), attrs)

      if category.persisted?
        category.custom_fields["nl_owner_id"] = current_user.id
        category.custom_fields["nl_adult"] = params[:adult].to_s == "true"
        category.custom_fields["nl_topic"] = topic[0, 60]
        category.save_custom_fields
        render_json_dump(id: category.id, slug: category.slug, url: "/c/#{category.slug}/#{category.id}")
      else
        render_json_error(category)
      end
    end
  end

  Discourse::Application.routes.append do
    get "/slava-dvora" => "slava_dvora#index", defaults: { format: :json }
    post "/nalavke/streets" => "nalavke_streets#create", defaults: { format: :json }
  end
end

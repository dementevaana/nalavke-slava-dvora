# name: nalavke-slava-dvora
# about: Рейтинги Слава двора за скользящие 7 дней
# version: 0.1
# authors: NaLavke
# url: https://github.com/dementevaana/nalavke-slava-dvora

after_initialize do
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

  Discourse::Application.routes.append do
    get "/slava-dvora" => "slava_dvora#index", defaults: { format: :json }
  end
end

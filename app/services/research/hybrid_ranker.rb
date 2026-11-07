module Research
  class HybridRanker
    CANDIDATES = 100

    def initialize(rows:, space:, query:, vector:, recency:, keyword: true)
      unless [true, false].include?(keyword) && (keyword || vector)
        raise Error.new("invalid_retrieval_channel")
      end
      @rows, @space, @query, @vector, @recency = rows, space, query, vector, recency
      @keyword = keyword
    end

    def call
      connection = ApplicationRecord.connection
      eligible = @rows.select("research_passages.id", "research_passages.search_vector").to_sql
      query = connection.quote(@query)
      channels = connection.transaction(requires_new: true) do
        previous = connection.select_value("SHOW statement_timeout")
        connection.execute("SET LOCAL statement_timeout = '5s'")
        keyword = @keyword ? connection.select_values(<<~SQL).map(&:to_i) : []
          WITH eligible AS MATERIALIZED (#{eligible})
          SELECT id FROM eligible
          WHERE search_vector @@ websearch_to_tsquery('english', #{query})
          ORDER BY ts_rank_cd(search_vector, websearch_to_tsquery('english', #{query}), 32) DESC, id
          LIMIT #{CANDIDATES}
        SQL
        vector = []
        if @vector
          unless Embedder.valid_vector?(@vector)
            raise Error.new("invalid_query_embedding")
          end
          values = connection.quote("[#{@vector.map(&:to_f).join(',')}]")
          # Materialize distances before ORDER BY: a future ANN index cannot truncate the eligible exact baseline.
          vector = connection.select_values(<<~SQL).map(&:to_i)
            WITH eligible AS MATERIALIZED (#{eligible}), distances AS MATERIALIZED (
              SELECT e.passage_id, e.embedding <=> #{values}::vector AS distance
              FROM research_embeddings e JOIN eligible ON eligible.id = e.passage_id
              WHERE e.space_id = #{@space.id.to_i} AND e.user_id = #{@space.user_id.to_i}
            )
            SELECT passage_id FROM distances WHERE distance <= 0.5 ORDER BY distance, passage_id LIMIT #{CANDIDATES}
          SQL
        end
        connection.execute("SET LOCAL statement_timeout = #{connection.quote(previous)}")
        [keyword, vector]
      end
      scores = Hash.new(0.0)
      channels.each { |ids| ids.each_with_index { |id, index| scores[id] += 1.0 / (61 + index) } }
      dates = @recency ? @rows.where(id: scores.keys).pluck("research_passages.id", "research_revisions.known_at").to_h : {}
      scores.sort_by { |id, score| [-score, @recency ? -(dates[id]&.to_f || 0) : 0, id] }
        .map { |id, score| { "passage_id" => id, "score" => score } }
    rescue ActiveRecord::QueryCanceled
      raise Error.new("retrieval_query_timeout")
    end
  end
end

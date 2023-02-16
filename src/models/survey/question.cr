class Survey
  class Question
    include Clear::Model
    self.table = "questions"

    column id : Int64, primary: true, presence: false
    column title : String
    column description : String?
    column type : String
    column options : JSON::Any, presence: false
    column required : Bool, presence: false
    column choices : JSON::Any, presence: false
    column max_rating : Int32?
    column tags : Array(String), presence: false

    has_many answers : Survey::Answer, foreign_key: "answer_id"

    timestamps

    # TODO: check question is not used by a survey before deleting
    # before :delete, :ensure_not_used

    before(:save) do |m|
      question_model = m.as(Question)
      question_model.clear_persisted if question_model.persisted? && Survey::Answer.query.where(question_id: question_model.id).count > 0
    end

    struct Responder
      include JSON::Serializable

      getter id : Int64?
      getter title : String? = nil
      getter description : String? = nil
      getter type : String? = nil
      getter options : JSON::Any? = nil
      getter required : Bool? = nil
      getter choices : JSON::Any? = nil
      getter max_rating : Int32? = nil
      getter tags : Array(String)? = nil

      def initialize(
        @id,
        @title = nil,
        @description = nil,
        @type = nil,
        @options = nil,
        @required = nil,
        @choices = nil,
        @max_rating = nil,
        @tags = nil
      )
      end

      def to_question(update : Bool = false)
        question = Survey::Question.new
        {% for key in [:title, :description, :type, :required, :max_rating, :tags] %}
          question.{{key.id}} = self.{{key.id}}.not_nil! unless self.{{key.id}}.nil?
        {% end %}

        {% for key in [:options, :choices] %}
          if json = {{key.id}}
            question.{{key.id}} = JSON.parse(json.to_json) unless update && json.as_h.empty?
          elsif !update
            question.{{key.id}} = JSON.parse("{}")
          end
        {% end %}

        question
      end
    end

    def as_json
      self.options = options_column.defined? ? self.options : JSON::Any.new({} of String => JSON::Any)
      self.required = required_column.defined? ? self.required : false
      self.choices = choices_column.defined? ? self.choices : JSON::Any.new({} of String => JSON::Any)
      self.tags = tags_column.defined? ? self.tags : [] of String

      Responder.new(
        id: self.id,
        title: self.title,
        description: self.description_column.value(nil),
        type: self.type,
        options: self.options,
        required: self.required,
        choices: self.choices,
        max_rating: self.max_rating_column.value(nil),
        tags: self.tags,
      )
    end

    def clear_persisted
      @persisted = false
      self.id_column.clear
      self.created_at_column.clear
      self.updated_at_column.clear
    end

    def validate
      validate_columns
    end

    private def validate_columns
      add_error("title", "must be defined") unless title_column.defined?
      add_error("type", "must be defined") unless type_column.defined?
    end
  end
end

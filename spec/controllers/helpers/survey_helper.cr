module SurveyHelper
  extend self

  def question_responders
    [
      Survey::Question::Responder.from_json({
        title:   "What is your favorite color?",
        type:    "single_choice",
        options: [
          {title: "Red"},
          {title: "Blue"},
          {title: "Green"},
        ],
      }.to_json),
      Survey::Question::Responder.from_json({
        title:   "What is your favorite animal?",
        type:    "single_choice",
        options: [
          {title: "Dog"},
          {title: "Cat"},
          {title: "Bird"},
        ],
      }.to_json),
      Survey::Question::Responder.from_json({
        title:   "What is your favorite food?",
        type:    "single_choice",
        options: [
          {title: "Pizza"},
          {title: "Burgers"},
          {title: "Salad"},
        ],
      }.to_json),
    ]
  end

  def create_questions : Array(Survey::Question)
    question_responders.map { |q| q.to_question.save! }
  end

  def survey_responder(questions_order = [] of Int64)
    Survey::Responder.from_json({
      title:          "New Survey",
      description:    "This is a new survey",
      question_order: questions_order,
      pages:          [{
        title:          "Page 1",
        question_order: questions_order,
      }],
    }.to_json)
  end

  def create_survey(questions_order = [] of Int64)
    survey_responder(questions_order).to_survey.save!
  end
end

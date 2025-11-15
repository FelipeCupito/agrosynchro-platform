variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "delay_seconds" {
  description = "The time in seconds that the delivery of all messages in the queue will be delayed"
  type        = number
  default     = 0
}

variable "max_message_size" {
  description = "The limit of how many bytes a message can contain before Amazon SQS rejects it"
  type        = number
  default     = 262144
}

variable "message_retention_seconds" {
  description = "The number of seconds Amazon SQS retains a message"
  type        = number
  default     = 1209600 # 14 days
}

variable "receive_wait_time_seconds" {
  description = "The time for which a ReceiveMessage call will wait for a message to arrive"
  type        = number
  default     = 10
}

variable "visibility_timeout_seconds" {
  description = "The visibility timeout for the queue"
  type        = number
  default     = 300 # 5 minutes
}

variable "max_receive_count" {
  description = "The number of times a message is delivered to the source queue before being moved to the dead-letter queue"
  type        = number
  default     = 3
}

variable "dlq_message_retention_seconds" {
  description = "The number of seconds Amazon SQS retains a message in the dead letter queue"
  type        = number
  default     = 1209600 # 14 days
}

variable "queue_name_suffix" {
  description = "Suffix for the main queue name (e.g., 'messages-queue', 'tasks-queue')"
  type        = string
  default     = "messages-queue"
}

variable "dlq_name_suffix" {
  description = "Suffix for the dead letter queue name (e.g., 'messages-dlq', 'tasks-dlq')"
  type        = string
  default     = "messages-dlq"
}

variable "additional_tags" {
  description = "Additional tags to apply to all SQS resources"
  type        = map(string)
  default     = {}
}

variable "queue_purpose" {
  description = "Purpose/type of the queue for tagging (e.g., 'sensor_messages', 'image_processing')"
  type        = string
  default     = "general"
}
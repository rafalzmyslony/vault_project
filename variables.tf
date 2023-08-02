variable "db_name" {
  description = "DB name for todo app"
  default     = "baza_danych"
}

variable "db_role_name" {
  description = "DB role name (user) for todo app"
  default     = "todo_uzytkownik"
}
variable "db_pass" {
  description = "DB password before changing for vault purposes"
  default     = "first_password"
}
variable "aws_account_id" {
  description = "Id of your AWS account"
  default     = "<set-your_aws_account-id>"
}
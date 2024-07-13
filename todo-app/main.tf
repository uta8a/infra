provider "google" {
  region  = var.region
  zone    = var.zone
  project = var.project
}

resource "google_firestore_database" "todo-app" {
  name        = "(default)" # 無料枠は `(default)` データベースが対象
  location_id = "nam5"
  type        = "FIRESTORE_NATIVE"
}

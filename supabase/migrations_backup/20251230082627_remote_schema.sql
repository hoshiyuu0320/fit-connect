drop policy "Clients can view own profile" on "public"."clients";

drop policy "Clients can delete own exercise records" on "public"."exercise_records";

drop policy "Clients can insert own exercise records" on "public"."exercise_records";

drop policy "Clients can update own exercise records" on "public"."exercise_records";

drop policy "Clients can view own exercise records" on "public"."exercise_records";

drop policy "Clients can delete own meal records" on "public"."meal_records";

drop policy "Clients can insert own meal records" on "public"."meal_records";

drop policy "Clients can update own meal records" on "public"."meal_records";

drop policy "Clients can view own meal records" on "public"."meal_records";

drop policy "Users can update own profile" on "public"."profiles";

drop policy "Clients can delete own weight records" on "public"."weight_records";

drop policy "Clients can insert own weight records" on "public"."weight_records";

drop policy "Clients can update own weight records" on "public"."weight_records";

drop policy "Clients can view own weight records" on "public"."weight_records";

alter table "public"."profiles" drop constraint "profiles_role_check";

alter table "public"."profiles" drop column "role";



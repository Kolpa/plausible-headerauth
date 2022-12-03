defmodule PlausibleWeb.AuthPlug do
  import Plug.Conn
  use Plausible.Repo

  def init(options) do
    options
  end

  def call(conn, _opts) do
    with id when is_integer(id) <- get_user_id_by_session_or_header(conn),
         %Plausible.Auth.User{} = user <- find_user(id) do
      Plausible.OpenTelemetry.add_user_attributes(user)
      Sentry.Context.set_user_context(%{id: user.id, name: user.name, email: user.email})
      assign(conn, :current_user, user)
    else
      nil -> conn
    end
  end

  defp get_user_id_by_session_or_header(conn) do
    cond do
      (user_email = List.first(get_req_header(conn, "x-auth-useremail"))) != nil ->
        user_id_by_email(user_email)

      is_integer(user_id = get_session(conn, :current_user_id)) ->
        user_id

      true ->
        nil
    end
  end

  defp user_id_by_email(email) do
    user_query =
      from(user in Plausible.Auth.User,
        where: user.email == ^email,
        limit: 1
      )

    case Repo.one(user_query) do
      nil ->
        nil

      user ->
        user.id
    end
  end

  defp find_user(user_id) do
    last_subscription_query =
      from(subscription in Plausible.Billing.Subscription,
        where: subscription.user_id == ^user_id,
        order_by: [desc: subscription.inserted_at],
        limit: 1
      )

    user_query =
      from(user in Plausible.Auth.User,
        left_join: last_subscription in subquery(last_subscription_query),
        on: last_subscription.user_id == user.id,
        left_join: subscription in Plausible.Billing.Subscription,
        on: subscription.id == last_subscription.id,
        where: user.id == ^user_id,
        preload: [subscription: subscription]
      )

    Repo.one(user_query)
  end
end

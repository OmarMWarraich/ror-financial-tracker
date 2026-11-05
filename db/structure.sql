\restrict Btr6rwYoTS9ksLNzwfGkacpJVomDQnmRkMjwpVlmbiAtLTIe8YJTyNnOz1O9ozt

-- Dumped from database version 16.15 (Debian 16.15-1.pgdg13+2)
-- Dumped by pg_dump version 16.15 (Debian 16.15-1.pgdg12+2)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: sandbox_reject_mutation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sandbox_reject_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION 'Synthetic ledger rows are append-only';
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: broker_connections; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.broker_connections (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    label character varying NOT NULL,
    product character varying DEFAULT 'exchange'::character varying NOT NULL,
    mode character varying DEFAULT 'read_only'::character varying NOT NULL,
    state character varying DEFAULT 'pending'::character varying NOT NULL,
    key_fingerprint character varying NOT NULL,
    api_key text,
    api_secret text,
    account_identifier text,
    balance_payload text,
    history_payload text,
    verified_permissions jsonb DEFAULT '[]'::jsonb NOT NULL,
    include_history boolean DEFAULT false NOT NULL,
    last_nonce bigint DEFAULT 0 NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    last_attempt_at timestamp(6) without time zone,
    received_at timestamp(6) without time zone,
    disconnected_at timestamp(6) without time zone,
    last_error character varying,
    elevation_state character varying DEFAULT 'not_requested'::character varying NOT NULL,
    elevation_requested_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT broker_exchange_only CHECK (((product)::text = 'exchange'::text)),
    CONSTRAINT broker_monitoring_only CHECK (((mode)::text = 'read_only'::text))
);


--
-- Name: broker_connections_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.broker_connections_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: broker_connections_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.broker_connections_id_seq OWNED BY public.broker_connections.id;


--
-- Name: equibles_connections; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.equibles_connections (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    api_key text,
    snapshot jsonb DEFAULT '{}'::jsonb NOT NULL,
    quota_date date,
    requests_used integer DEFAULT 0 NOT NULL,
    last_attempt_at timestamp(6) without time zone,
    last_success_at timestamp(6) without time zone,
    last_error character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT equibles_nonnegative_usage CHECK ((requests_used >= 0))
);


--
-- Name: equibles_connections_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.equibles_connections_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: equibles_connections_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.equibles_connections_id_seq OWNED BY public.equibles_connections.id;


--
-- Name: friendships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.friendships (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    friend_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: friendships_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.friendships_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: friendships_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.friendships_id_seq OWNED BY public.friendships.id;


--
-- Name: sandbox_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sandbox_accounts (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    environment character varying DEFAULT 'synthetic'::character varying NOT NULL,
    currency character varying DEFAULT 'USD'::character varying NOT NULL,
    initial_cash numeric(14,2) NOT NULL,
    cash numeric(14,2) NOT NULL,
    quantity integer DEFAULT 0 NOT NULL,
    cost_basis numeric(14,2) DEFAULT 0.0 NOT NULL,
    fixture_key character varying NOT NULL,
    fixture_loaded_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT sandbox_account_bounds CHECK ((((environment)::text = 'synthetic'::text) AND ((currency)::text = 'USD'::text) AND (initial_cash > (0)::numeric) AND (initial_cash <= (10000)::numeric) AND (cash >= (0)::numeric) AND (quantity >= 0) AND (cost_basis >= (0)::numeric)))
);


--
-- Name: sandbox_accounts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sandbox_accounts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sandbox_accounts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sandbox_accounts_id_seq OWNED BY public.sandbox_accounts.id;


--
-- Name: sandbox_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sandbox_events (
    id bigint NOT NULL,
    sandbox_account_id bigint NOT NULL,
    kind character varying NOT NULL,
    details jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: sandbox_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sandbox_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sandbox_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sandbox_events_id_seq OWNED BY public.sandbox_events.id;


--
-- Name: sandbox_mandates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sandbox_mandates (
    id bigint NOT NULL,
    sandbox_account_id bigint NOT NULL,
    state character varying DEFAULT 'draft'::character varying NOT NULL,
    rule_version character varying DEFAULT 'trend-v1'::character varying NOT NULL,
    instrument character varying DEFAULT 'SYNTH-ALPHA'::character varying NOT NULL,
    environment character varying DEFAULT 'synthetic'::character varying NOT NULL,
    session character varying DEFAULT 'fixture'::character varying NOT NULL,
    order_type character varying DEFAULT 'synthetic_market'::character varying NOT NULL,
    capital_limit numeric(14,2) NOT NULL,
    max_notional numeric(14,2) NOT NULL,
    max_quantity integer NOT NULL,
    max_exposure numeric(14,2) NOT NULL,
    loss_limit numeric(14,2) NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    approved_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT sandbox_mandate_bounds CHECK ((((state)::text = ANY ((ARRAY['draft'::character varying, 'active'::character varying, 'paused'::character varying, 'revoked'::character varying])::text[])) AND (capital_limit > (0)::numeric) AND (capital_limit <= (10000)::numeric) AND (max_notional > (0)::numeric) AND (max_notional <= capital_limit) AND (max_quantity > 0) AND (max_quantity <= 100) AND (max_exposure > (0)::numeric) AND (max_exposure <= capital_limit) AND (loss_limit > (0)::numeric) AND (loss_limit <= capital_limit)))
);


--
-- Name: sandbox_mandates_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sandbox_mandates_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sandbox_mandates_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sandbox_mandates_id_seq OWNED BY public.sandbox_mandates.id;


--
-- Name: sandbox_orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sandbox_orders (
    id bigint NOT NULL,
    sandbox_account_id bigint NOT NULL,
    sandbox_mandate_id bigint NOT NULL,
    user_id bigint NOT NULL,
    request_key character varying NOT NULL,
    fixture_key character varying NOT NULL,
    fixture_digest character varying NOT NULL,
    side character varying NOT NULL,
    state character varying NOT NULL,
    quantity integer NOT NULL,
    price numeric(14,2) NOT NULL,
    fee numeric(14,2) NOT NULL,
    reserved_cash numeric(14,2) NOT NULL,
    reserved_quantity integer NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT sandbox_order_bounds CHECK ((((state)::text = 'filled'::text) AND ((side)::text = ANY ((ARRAY['buy'::character varying, 'sell'::character varying])::text[])) AND (quantity > 0) AND (price > (0)::numeric) AND (fee >= (0)::numeric) AND (reserved_cash >= (0)::numeric) AND (reserved_quantity >= 0)))
);


--
-- Name: sandbox_orders_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sandbox_orders_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sandbox_orders_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sandbox_orders_id_seq OWNED BY public.sandbox_orders.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: stocks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stocks (
    id bigint NOT NULL,
    ticker character varying,
    name character varying,
    last_price numeric,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: stocks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.stocks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: stocks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.stocks_id_seq OWNED BY public.stocks.id;


--
-- Name: user_stocks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_stocks (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    stock_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: user_stocks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_stocks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_stocks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_stocks_id_seq OWNED BY public.user_stocks.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    email character varying DEFAULT ''::character varying NOT NULL,
    encrypted_password character varying DEFAULT ''::character varying NOT NULL,
    reset_password_token character varying,
    reset_password_sent_at timestamp(6) without time zone,
    remember_created_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    first_name character varying,
    last_name character varying,
    sensitive_action_failures integer DEFAULT 0 NOT NULL,
    sensitive_action_locked_until timestamp(6) without time zone
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: broker_connections id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.broker_connections ALTER COLUMN id SET DEFAULT nextval('public.broker_connections_id_seq'::regclass);


--
-- Name: equibles_connections id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.equibles_connections ALTER COLUMN id SET DEFAULT nextval('public.equibles_connections_id_seq'::regclass);


--
-- Name: friendships id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.friendships ALTER COLUMN id SET DEFAULT nextval('public.friendships_id_seq'::regclass);


--
-- Name: sandbox_accounts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sandbox_accounts ALTER COLUMN id SET DEFAULT nextval('public.sandbox_accounts_id_seq'::regclass);


--
-- Name: sandbox_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sandbox_events ALTER COLUMN id SET DEFAULT nextval('public.sandbox_events_id_seq'::regclass);


--
-- Name: sandbox_mandates id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sandbox_mandates ALTER COLUMN id SET DEFAULT nextval('public.sandbox_mandates_id_seq'::regclass);


--
-- Name: sandbox_orders id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sandbox_orders ALTER COLUMN id SET DEFAULT nextval('public.sandbox_orders_id_seq'::regclass);


--
-- Name: stocks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stocks ALTER COLUMN id SET DEFAULT nextval('public.stocks_id_seq'::regclass);


--
-- Name: user_stocks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_stocks ALTER COLUMN id SET DEFAULT nextval('public.user_stocks_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: broker_connections broker_connections_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.broker_connections
    ADD CONSTRAINT broker_connections_pkey PRIMARY KEY (id);


--
-- Name: equibles_connections equibles_connections_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.equibles_connections
    ADD CONSTRAINT equibles_connections_pkey PRIMARY KEY (id);


--
-- Name: friendships friendships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.friendships
    ADD CONSTRAINT friendships_pkey PRIMARY KEY (id);


--
-- Name: sandbox_accounts sandbox_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sandbox_accounts
    ADD CONSTRAINT sandbox_accounts_pkey PRIMARY KEY (id);


--
-- Name: sandbox_events sandbox_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sandbox_events
    ADD CONSTRAINT sandbox_events_pkey PRIMARY KEY (id);


--
-- Name: sandbox_mandates sandbox_mandates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sandbox_mandates
    ADD CONSTRAINT sandbox_mandates_pkey PRIMARY KEY (id);


--
-- Name: sandbox_orders sandbox_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sandbox_orders
    ADD CONSTRAINT sandbox_orders_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: stocks stocks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stocks
    ADD CONSTRAINT stocks_pkey PRIMARY KEY (id);


--
-- Name: user_stocks user_stocks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_stocks
    ADD CONSTRAINT user_stocks_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: index_broker_connections_on_key_fingerprint; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_broker_connections_on_key_fingerprint ON public.broker_connections USING btree (key_fingerprint);


--
-- Name: index_broker_connections_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_broker_connections_on_user_id ON public.broker_connections USING btree (user_id);


--
-- Name: index_equibles_connections_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_equibles_connections_on_user_id ON public.equibles_connections USING btree (user_id);


--
-- Name: index_friendships_on_friend_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_friendships_on_friend_id ON public.friendships USING btree (friend_id);


--
-- Name: index_friendships_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_friendships_on_user_id ON public.friendships USING btree (user_id);


--
-- Name: index_sandbox_accounts_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_sandbox_accounts_on_user_id ON public.sandbox_accounts USING btree (user_id);


--
-- Name: index_sandbox_events_on_sandbox_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sandbox_events_on_sandbox_account_id ON public.sandbox_events USING btree (sandbox_account_id);


--
-- Name: index_sandbox_mandates_on_sandbox_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sandbox_mandates_on_sandbox_account_id ON public.sandbox_mandates USING btree (sandbox_account_id);


--
-- Name: index_sandbox_orders_on_sandbox_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sandbox_orders_on_sandbox_account_id ON public.sandbox_orders USING btree (sandbox_account_id);


--
-- Name: index_sandbox_orders_on_sandbox_mandate_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sandbox_orders_on_sandbox_mandate_id ON public.sandbox_orders USING btree (sandbox_mandate_id);


--
-- Name: index_sandbox_orders_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sandbox_orders_on_user_id ON public.sandbox_orders USING btree (user_id);


--
-- Name: index_sandbox_orders_on_user_id_and_request_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_sandbox_orders_on_user_id_and_request_key ON public.sandbox_orders USING btree (user_id, request_key);


--
-- Name: index_user_stocks_on_stock_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_user_stocks_on_stock_id ON public.user_stocks USING btree (stock_id);


--
-- Name: index_user_stocks_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_user_stocks_on_user_id ON public.user_stocks USING btree (user_id);


--
-- Name: index_users_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email ON public.users USING btree (email);


--
-- Name: index_users_on_reset_password_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_reset_password_token ON public.users USING btree (reset_password_token);


--
-- Name: one_active_sandbox_mandate; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX one_active_sandbox_mandate ON public.sandbox_mandates USING btree (sandbox_account_id) WHERE ((state)::text = 'active'::text);


--
-- Name: sandbox_events sandbox_events_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sandbox_events_immutable BEFORE DELETE OR UPDATE ON public.sandbox_events FOR EACH ROW EXECUTE FUNCTION public.sandbox_reject_mutation();


--
-- Name: sandbox_orders sandbox_orders_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sandbox_orders_immutable BEFORE DELETE OR UPDATE ON public.sandbox_orders FOR EACH ROW EXECUTE FUNCTION public.sandbox_reject_mutation();


--
-- Name: user_stocks fk_rails_15a036aef2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_stocks
    ADD CONSTRAINT fk_rails_15a036aef2 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: sandbox_events fk_rails_341e84e683; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sandbox_events
    ADD CONSTRAINT fk_rails_341e84e683 FOREIGN KEY (sandbox_account_id) REFERENCES public.sandbox_accounts(id);


--
-- Name: equibles_connections fk_rails_4991fd602d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.equibles_connections
    ADD CONSTRAINT fk_rails_4991fd602d FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: user_stocks fk_rails_62699afff5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_stocks
    ADD CONSTRAINT fk_rails_62699afff5 FOREIGN KEY (stock_id) REFERENCES public.stocks(id);


--
-- Name: sandbox_orders fk_rails_92924e3593; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sandbox_orders
    ADD CONSTRAINT fk_rails_92924e3593 FOREIGN KEY (sandbox_mandate_id) REFERENCES public.sandbox_mandates(id);


--
-- Name: sandbox_accounts fk_rails_986e222674; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sandbox_accounts
    ADD CONSTRAINT fk_rails_986e222674 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: sandbox_orders fk_rails_ad434e8514; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sandbox_orders
    ADD CONSTRAINT fk_rails_ad434e8514 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: sandbox_mandates fk_rails_b0292a97d4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sandbox_mandates
    ADD CONSTRAINT fk_rails_b0292a97d4 FOREIGN KEY (sandbox_account_id) REFERENCES public.sandbox_accounts(id);


--
-- Name: sandbox_orders fk_rails_c38a321c0f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sandbox_orders
    ADD CONSTRAINT fk_rails_c38a321c0f FOREIGN KEY (sandbox_account_id) REFERENCES public.sandbox_accounts(id);


--
-- Name: broker_connections fk_rails_ca90ba462e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.broker_connections
    ADD CONSTRAINT fk_rails_ca90ba462e FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: friendships fk_rails_d78dc9c7fd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.friendships
    ADD CONSTRAINT fk_rails_d78dc9c7fd FOREIGN KEY (friend_id) REFERENCES public.users(id);


--
-- Name: friendships fk_rails_e3733b59b7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.friendships
    ADD CONSTRAINT fk_rails_e3733b59b7 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- PostgreSQL database dump complete
--

\unrestrict Btr6rwYoTS9ksLNzwfGkacpJVomDQnmRkMjwpVlmbiAtLTIe8YJTyNnOz1O9ozt

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20261105050000'),
('20261105043000'),
('20261105042000'),
('20240403103018'),
('20240403093954'),
('20240401185246'),
('20240328142412'),
('20240328083107');

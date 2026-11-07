\restrict bj7YAv1GOF6VFyl4zZZNcllC5DUadEmRsUOZefgPEKtifO4PuE3kFBprDhIXNaL

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
-- Name: vector; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA public;


--
-- Name: EXTENSION vector; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION vector IS 'vector data type and ivfflat and hnsw access methods';


--
-- Name: research_agent_identity_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.research_agent_identity_guard() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF ROW(NEW.user_id, NEW.request_key, NEW.query_digest, NEW.selectors, NEW.provider,
         NEW.model, NEW.prompt_version, NEW.deadline_at)
    IS DISTINCT FROM ROW(OLD.user_id, OLD.request_key, OLD.query_digest, OLD.selectors,
         OLD.provider, OLD.model, OLD.prompt_version, OLD.deadline_at)
    OR (OLD.credential_fingerprints <> '{}'::jsonb AND NEW.credential_fingerprints IS DISTINCT FROM OLD.credential_fingerprints)
  THEN
    RAISE EXCEPTION 'research agent request identity is immutable';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: research_conversation_identity_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.research_conversation_identity_guard() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF ROW(NEW.user_id, NEW.scope, NEW.limits, NEW.expires_at)
    IS DISTINCT FROM ROW(OLD.user_id, OLD.scope, OLD.limits, OLD.expires_at)
  THEN RAISE EXCEPTION 'research conversation identity is immutable'; END IF;
  RETURN NEW;
END;
$$;


--
-- Name: research_durable_identity_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.research_durable_identity_guard() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF ROW(NEW.conversation_id, NEW.limits, NEW.pricing, NEW.workflow_version, NEW.budget_date,
         NEW.reserved_cost_nanos, NEW.reserved_source_requests, NEW.source_connection_id)
    IS DISTINCT FROM ROW(OLD.conversation_id, OLD.limits, OLD.pricing, OLD.workflow_version, OLD.budget_date,
         OLD.reserved_cost_nanos, OLD.reserved_source_requests, OLD.source_connection_id)
    OR (OLD.state <> NEW.state AND NOT (
      (OLD.state = 'queued' AND NEW.state IN ('running','failed','cancelled','interrupted')) OR
      (OLD.state = 'running' AND NEW.state IN ('completed','no_evidence','failed','cancelled','interrupted'))))
  THEN RAISE EXCEPTION 'research durable run identity or transition is invalid'; END IF;
  RETURN NEW;
END;
$$;


--
-- Name: research_retrieval_agent_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.research_retrieval_agent_guard() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF OLD.agent_run_id IS NOT NULL AND NEW.agent_run_id IS DISTINCT FROM OLD.agent_run_id THEN
    RAISE EXCEPTION 'research retrieval agent association is immutable';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: research_space_preserve_identity(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.research_space_preserve_identity() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF ROW(NEW.user_id, NEW.provider, NEW.model, NEW.model_version, NEW.dimensions,
         NEW.distance, NEW.preprocessing_version, NEW.chunker_version)
     IS DISTINCT FROM
     ROW(OLD.user_id, OLD.provider, OLD.model, OLD.model_version, OLD.dimensions,
         OLD.distance, OLD.preprocessing_version, OLD.chunker_version) THEN
    RAISE EXCEPTION 'Embedding space identity is immutable; create a new version';
  END IF;
  RETURN NEW;
END;
$$;


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
    quota_observation jsonb DEFAULT '{}'::jsonb NOT NULL,
    quota_key_digest character varying,
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
-- Name: research_agent_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.research_agent_runs (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    request_key character varying NOT NULL,
    query_digest character varying NOT NULL,
    selectors jsonb NOT NULL,
    credential_fingerprints jsonb DEFAULT '{}'::jsonb NOT NULL,
    provider character varying NOT NULL,
    model character varying NOT NULL,
    prompt_version character varying NOT NULL,
    state character varying DEFAULT 'running'::character varying NOT NULL,
    source_requests integer DEFAULT 0 NOT NULL,
    tool_calls integer DEFAULT 0 NOT NULL,
    deadline_at timestamp(6) without time zone NOT NULL,
    error_code character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    conversation_id bigint,
    limits jsonb DEFAULT '{}'::jsonb NOT NULL,
    pricing jsonb DEFAULT '{}'::jsonb NOT NULL,
    workflow_version character varying,
    budget_date date,
    reserved_cost_nanos bigint DEFAULT 0 NOT NULL,
    reserved_source_requests integer DEFAULT 0 NOT NULL,
    cancel_requested_at timestamp(6) without time zone,
    lease_token character varying,
    lease_until timestamp(6) without time zone,
    enqueued_at timestamp(6) without time zone,
    enqueue_attempts integer DEFAULT 0 NOT NULL,
    finished_at timestamp(6) without time zone,
    source_connection_id bigint,
    CONSTRAINT research_agent_provider_model CHECK (((((provider)::text = 'fixture'::text) AND ((model)::text = 'original-fixture-v1'::text)) OR (((provider)::text = 'openai'::text) AND ((model)::text = 'gpt-5.4-mini-2026-03-17'::text)))),
    CONSTRAINT research_agent_run_contract CHECK ((((query_digest)::text ~ '^[0-9a-f]{64}$'::text) AND ((request_key)::text <> ''::text) AND ((provider)::text = ANY ((ARRAY['openai'::character varying, 'fixture'::character varying])::text[])) AND ((state)::text = ANY ((ARRAY['queued'::character varying, 'running'::character varying, 'completed'::character varying, 'no_evidence'::character varying, 'failed'::character varying, 'cancelled'::character varying, 'interrupted'::character varying])::text[])) AND ((source_requests >= 0) AND (source_requests <= 16)) AND ((tool_calls >= 0) AND (tool_calls <= 6)) AND (jsonb_typeof(selectors) = 'object'::text) AND (jsonb_typeof(credential_fingerprints) = 'object'::text) AND (jsonb_typeof(limits) = 'object'::text) AND (jsonb_typeof(pricing) = 'object'::text) AND ((reserved_cost_nanos >= 0) AND (reserved_cost_nanos <= 50000000)) AND ((reserved_source_requests >= 0) AND (reserved_source_requests <= 16)) AND ((conversation_id IS NULL) OR ((budget_date IS NOT NULL) AND (workflow_version IS NOT NULL)))))
);


--
-- Name: research_agent_runs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.research_agent_runs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: research_agent_runs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.research_agent_runs_id_seq OWNED BY public.research_agent_runs.id;


--
-- Name: research_conversations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.research_conversations (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    scope jsonb NOT NULL,
    limits jsonb NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: research_conversations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.research_conversations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: research_conversations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.research_conversations_id_seq OWNED BY public.research_conversations.id;


--
-- Name: research_documents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.research_documents (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    provider character varying NOT NULL,
    source_kind character varying NOT NULL,
    source_id character varying NOT NULL,
    instrument_identity character varying NOT NULL,
    listing_identity character varying NOT NULL,
    fiscal_year integer NOT NULL,
    fiscal_period character varying NOT NULL,
    citation_url character varying NOT NULL,
    entitlement_reference character varying NOT NULL,
    rights_expires_at timestamp(6) without time zone NOT NULL,
    revoked_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    current_revision_id bigint,
    ingestion_generation integer DEFAULT 0 NOT NULL,
    CONSTRAINT research_document_generation CHECK ((ingestion_generation >= 0)),
    CONSTRAINT research_document_identity CHECK ((((provider)::text <> ''::text) AND ((source_id)::text <> ''::text) AND ((instrument_identity)::text <> ''::text) AND ((listing_identity)::text <> ''::text) AND ((entitlement_reference)::text <> ''::text) AND ((citation_url)::text ~ '^https://[^[:space:]]+$'::text) AND (fiscal_year > 0) AND ((fiscal_period)::text = ANY ((ARRAY['Q1'::character varying, 'Q2'::character varying, 'Q3'::character varying, 'Q4'::character varying, 'FY'::character varying])::text[])) AND ((source_kind)::text = ANY ((ARRAY['earnings_brief'::character varying, 'earnings_transcript'::character varying, 'filing'::character varying])::text[]))))
);


--
-- Name: research_documents_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.research_documents_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: research_documents_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.research_documents_id_seq OWNED BY public.research_documents.id;


--
-- Name: research_embedding_attempts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.research_embedding_attempts (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    ingestion_id bigint,
    batch_key character varying NOT NULL,
    generation integer NOT NULL,
    budget_date date NOT NULL,
    state character varying DEFAULT 'reserved'::character varying NOT NULL,
    reserved_tokens integer NOT NULL,
    reserved_cost_nanos bigint NOT NULL,
    actual_tokens integer,
    actual_cost_nanos bigint,
    error_code character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    retrieval_id bigint,
    CONSTRAINT research_embedding_attempt_budget CHECK ((((state)::text = ANY ((ARRAY['reserved'::character varying, 'dispatched'::character varying, 'settled'::character varying, 'uncertain'::character varying, 'released'::character varying])::text[])) AND ((reserved_tokens >= 1) AND (reserved_tokens <= 3200)) AND (reserved_cost_nanos >= 0) AND ((actual_tokens IS NULL) OR (actual_tokens >= 0)) AND ((actual_cost_nanos IS NULL) OR (actual_cost_nanos >= 0)))),
    CONSTRAINT research_embedding_attempt_owner_request CHECK (((ingestion_id IS NULL) <> (retrieval_id IS NULL)))
);


--
-- Name: research_embedding_attempts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.research_embedding_attempts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: research_embedding_attempts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.research_embedding_attempts_id_seq OWNED BY public.research_embedding_attempts.id;


--
-- Name: research_embedding_spaces; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.research_embedding_spaces (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    provider character varying NOT NULL,
    model character varying NOT NULL,
    model_version character varying NOT NULL,
    dimensions integer DEFAULT 1536 NOT NULL,
    distance character varying DEFAULT 'cosine'::character varying NOT NULL,
    preprocessing_version character varying NOT NULL,
    chunker_version character varying NOT NULL,
    state character varying DEFAULT 'building'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT research_space_contract CHECK ((((provider)::text <> ''::text) AND ((model)::text <> ''::text) AND ((model_version)::text <> ''::text) AND ((preprocessing_version)::text <> ''::text) AND ((chunker_version)::text <> ''::text) AND (dimensions = 1536) AND ((distance)::text = 'cosine'::text) AND ((state)::text = ANY ((ARRAY['building'::character varying, 'active'::character varying, 'retired'::character varying])::text[]))))
);


--
-- Name: research_embedding_spaces_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.research_embedding_spaces_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: research_embedding_spaces_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.research_embedding_spaces_id_seq OWNED BY public.research_embedding_spaces.id;


--
-- Name: research_embeddings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.research_embeddings (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    passage_id bigint NOT NULL,
    space_id bigint NOT NULL,
    preprocessing_version character varying NOT NULL,
    chunker_version character varying NOT NULL,
    input_checksum character varying NOT NULL,
    embedding public.vector(1536) NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT research_embedding_nonzero CHECK ((public.vector_norm(embedding) > (0)::double precision))
);


--
-- Name: research_embeddings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.research_embeddings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: research_embeddings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.research_embeddings_id_seq OWNED BY public.research_embeddings.id;


--
-- Name: research_ingestions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.research_ingestions (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    space_id bigint NOT NULL,
    document_id bigint,
    request_key character varying NOT NULL,
    provider character varying NOT NULL,
    source_kind character varying NOT NULL,
    listing_identity character varying NOT NULL,
    fiscal_year integer NOT NULL,
    fiscal_quarter integer NOT NULL,
    fixture_version character varying,
    source_revision character varying,
    state character varying DEFAULT 'pending'::character varying NOT NULL,
    generation integer DEFAULT 0 NOT NULL,
    document_generation integer,
    lease_token character varying,
    lease_expires_at timestamp(6) without time zone,
    credential_fingerprint character varying,
    source_requests integer DEFAULT 0 NOT NULL,
    error_code character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT research_ingestion_contract CHECK ((((state)::text = ANY ((ARRAY['pending'::character varying, 'fetching'::character varying, 'chunking'::character varying, 'embedding'::character varying, 'ready'::character varying, 'failed'::character varying])::text[])) AND ((provider)::text = ANY ((ARRAY['synthetic'::character varying, 'equibles'::character varying])::text[])) AND ((source_kind)::text = ANY ((ARRAY['earnings_transcript'::character varying, 'earnings_brief'::character varying])::text[])) AND ((fiscal_year >= 1900) AND (fiscal_year <= 2200)) AND ((fiscal_quarter >= 1) AND (fiscal_quarter <= 4)) AND (generation >= 0) AND ((source_requests >= 0) AND (source_requests <= 3)) AND ((request_key)::text <> ''::text)))
);


--
-- Name: research_ingestions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.research_ingestions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: research_ingestions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.research_ingestions_id_seq OWNED BY public.research_ingestions.id;


--
-- Name: research_messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.research_messages (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    conversation_id bigint NOT NULL,
    run_id bigint NOT NULL,
    role character varying NOT NULL,
    state character varying NOT NULL,
    content text,
    source_ids jsonb DEFAULT '[]'::jsonb NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT research_message_contract CHECK ((((role)::text = ANY ((ARRAY['user'::character varying, 'assistant'::character varying])::text[])) AND ((state)::text = ANY ((ARRAY['submitted'::character varying, 'complete'::character varying, 'incomplete'::character varying, 'redacted'::character varying])::text[])) AND (jsonb_typeof(source_ids) = 'array'::text)))
);


--
-- Name: research_messages_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.research_messages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: research_messages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.research_messages_id_seq OWNED BY public.research_messages.id;


--
-- Name: research_model_attempts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.research_model_attempts (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    run_id bigint NOT NULL,
    step integer NOT NULL,
    budget_date date NOT NULL,
    state character varying DEFAULT 'reserved'::character varying NOT NULL,
    reserved_input_tokens integer NOT NULL,
    reserved_output_tokens integer NOT NULL,
    reserved_cost_nanos bigint NOT NULL,
    actual_input_tokens integer,
    actual_output_tokens integer,
    actual_cost_nanos bigint,
    error_code character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT research_model_attempt_contract CHECK ((((step >= 1) AND (step <= 4)) AND ((state)::text = ANY ((ARRAY['reserved'::character varying, 'dispatched'::character varying, 'settled'::character varying, 'uncertain'::character varying, 'released'::character varying])::text[])) AND ((reserved_input_tokens >= 1) AND (reserved_input_tokens <= 10000)) AND ((reserved_output_tokens >= 1) AND (reserved_output_tokens <= 4096)) AND (reserved_cost_nanos >= 0) AND ((actual_input_tokens IS NULL) OR (actual_input_tokens >= 0)) AND ((actual_output_tokens IS NULL) OR (actual_output_tokens >= 0)) AND ((actual_cost_nanos IS NULL) OR (actual_cost_nanos >= 0))))
);


--
-- Name: research_model_attempts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.research_model_attempts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: research_model_attempts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.research_model_attempts_id_seq OWNED BY public.research_model_attempts.id;


--
-- Name: research_passages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.research_passages (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    revision_id bigint NOT NULL,
    preprocessing_version character varying NOT NULL,
    chunker_version character varying NOT NULL,
    "position" integer NOT NULL,
    start_char integer NOT NULL,
    end_char integer NOT NULL,
    start_line integer,
    end_line integer,
    speaker character varying,
    token_count integer NOT NULL,
    content text NOT NULL,
    checksum character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    source_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    search_vector tsvector GENERATED ALWAYS AS (to_tsvector('english'::regconfig, content)) STORED,
    CONSTRAINT research_passage_content_and_position CHECK ((((preprocessing_version)::text <> ''::text) AND ((chunker_version)::text <> ''::text) AND ("position" >= 0) AND (start_char >= 0) AND (end_char > start_char) AND ((end_char - start_char) = char_length(content)) AND (token_count > 0) AND (token_count <= 800) AND ((checksum)::text = encode(sha256(convert_to(content, 'UTF8'::name)), 'hex'::text)) AND (((start_line IS NULL) AND (end_line IS NULL)) OR ((start_line IS NOT NULL) AND (end_line IS NOT NULL) AND (start_line > 0) AND (end_line >= start_line)))))
);


--
-- Name: research_passages_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.research_passages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: research_passages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.research_passages_id_seq OWNED BY public.research_passages.id;


--
-- Name: research_retrievals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.research_retrievals (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    space_id bigint NOT NULL,
    request_key character varying NOT NULL,
    query_digest character varying NOT NULL,
    selectors jsonb NOT NULL,
    latest_event jsonb DEFAULT '{}'::jsonb NOT NULL,
    selection jsonb DEFAULT '[]'::jsonb NOT NULL,
    state character varying DEFAULT 'pending'::character varying NOT NULL,
    generation integer DEFAULT 0 NOT NULL,
    source_requests integer DEFAULT 0 NOT NULL,
    credential_fingerprint character varying,
    error_code character varying,
    deadline_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    agent_run_id bigint,
    CONSTRAINT research_retrieval_contract CHECK ((((request_key)::text <> ''::text) AND ((query_digest)::text ~ '^[0-9a-f]{64}$'::text) AND (generation >= 0) AND ((source_requests >= 0) AND (source_requests <= 2)) AND ((state)::text = ANY ((ARRAY['pending'::character varying, 'retrieving'::character varying, 'ready'::character varying, 'no_evidence'::character varying, 'stale_only'::character varying, 'failed'::character varying])::text[])) AND (jsonb_typeof(selectors) = 'object'::text) AND (jsonb_typeof(latest_event) = 'object'::text) AND (jsonb_typeof(selection) = 'array'::text)))
);


--
-- Name: research_retrievals_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.research_retrievals_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: research_retrievals_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.research_retrievals_id_seq OWNED BY public.research_retrievals.id;


--
-- Name: research_revisions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.research_revisions (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    document_id bigint NOT NULL,
    source_revision character varying NOT NULL,
    content text NOT NULL,
    checksum character varying NOT NULL,
    event_at timestamp(6) without time zone,
    published_at timestamp(6) without time zone,
    known_at timestamp(6) without time zone,
    received_at timestamp(6) without time zone NOT NULL,
    indexed_at timestamp(6) without time zone,
    fresh_until timestamp(6) without time zone,
    expires_at timestamp(6) without time zone NOT NULL,
    revoked_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    index_state character varying DEFAULT 'pending'::character varying NOT NULL,
    source_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    superseded_at timestamp(6) without time zone,
    temporal_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    verified_at timestamp(6) without time zone,
    CONSTRAINT research_revision_content_and_lifetime CHECK ((((source_revision)::text <> ''::text) AND (content <> ''::text) AND ((checksum)::text = encode(sha256(convert_to(content, 'UTF8'::name)), 'hex'::text)) AND (expires_at > received_at) AND ((fresh_until IS NULL) OR (fresh_until <= expires_at)))),
    CONSTRAINT research_revision_index_state CHECK (((index_state)::text = ANY ((ARRAY['pending'::character varying, 'ready'::character varying, 'failed'::character varying])::text[]))),
    CONSTRAINT research_temporal_metadata_object CHECK ((jsonb_typeof(temporal_metadata) = 'object'::text)),
    CONSTRAINT research_verification_after_receipt CHECK (((verified_at IS NULL) OR (verified_at >= received_at)))
);


--
-- Name: research_revisions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.research_revisions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: research_revisions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.research_revisions_id_seq OWNED BY public.research_revisions.id;


--
-- Name: research_tool_attempts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.research_tool_attempts (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    run_id bigint NOT NULL,
    call_id character varying NOT NULL,
    name character varying NOT NULL,
    arguments_digest character varying NOT NULL,
    state character varying NOT NULL,
    source_id character varying,
    error_code character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT research_tool_attempt_contract CHECK ((((name)::text = ANY ((ARRAY['GetEarningsCallEvent'::character varying, 'GetEarningsBrief'::character varying, 'GetEarningsCallTranscript'::character varying])::text[])) AND ((arguments_digest)::text ~ '^[0-9a-f]{64}$'::text) AND ((state)::text = ANY ((ARRAY['dispatched'::character varying, 'settled'::character varying, 'cached'::character varying, 'failed'::character varying, 'uncertain'::character varying])::text[]))))
);


--
-- Name: research_tool_attempts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.research_tool_attempts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: research_tool_attempts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.research_tool_attempts_id_seq OWNED BY public.research_tool_attempts.id;


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
-- Name: research_agent_runs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_agent_runs ALTER COLUMN id SET DEFAULT nextval('public.research_agent_runs_id_seq'::regclass);


--
-- Name: research_conversations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_conversations ALTER COLUMN id SET DEFAULT nextval('public.research_conversations_id_seq'::regclass);


--
-- Name: research_documents id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_documents ALTER COLUMN id SET DEFAULT nextval('public.research_documents_id_seq'::regclass);


--
-- Name: research_embedding_attempts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_embedding_attempts ALTER COLUMN id SET DEFAULT nextval('public.research_embedding_attempts_id_seq'::regclass);


--
-- Name: research_embedding_spaces id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_embedding_spaces ALTER COLUMN id SET DEFAULT nextval('public.research_embedding_spaces_id_seq'::regclass);


--
-- Name: research_embeddings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_embeddings ALTER COLUMN id SET DEFAULT nextval('public.research_embeddings_id_seq'::regclass);


--
-- Name: research_ingestions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_ingestions ALTER COLUMN id SET DEFAULT nextval('public.research_ingestions_id_seq'::regclass);


--
-- Name: research_messages id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_messages ALTER COLUMN id SET DEFAULT nextval('public.research_messages_id_seq'::regclass);


--
-- Name: research_model_attempts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_model_attempts ALTER COLUMN id SET DEFAULT nextval('public.research_model_attempts_id_seq'::regclass);


--
-- Name: research_passages id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_passages ALTER COLUMN id SET DEFAULT nextval('public.research_passages_id_seq'::regclass);


--
-- Name: research_retrievals id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_retrievals ALTER COLUMN id SET DEFAULT nextval('public.research_retrievals_id_seq'::regclass);


--
-- Name: research_revisions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_revisions ALTER COLUMN id SET DEFAULT nextval('public.research_revisions_id_seq'::regclass);


--
-- Name: research_tool_attempts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_tool_attempts ALTER COLUMN id SET DEFAULT nextval('public.research_tool_attempts_id_seq'::regclass);


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
-- Name: research_agent_runs research_agent_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_agent_runs
    ADD CONSTRAINT research_agent_runs_pkey PRIMARY KEY (id);


--
-- Name: research_conversations research_conversations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_conversations
    ADD CONSTRAINT research_conversations_pkey PRIMARY KEY (id);


--
-- Name: research_documents research_documents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_documents
    ADD CONSTRAINT research_documents_pkey PRIMARY KEY (id);


--
-- Name: research_embedding_attempts research_embedding_attempts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_embedding_attempts
    ADD CONSTRAINT research_embedding_attempts_pkey PRIMARY KEY (id);


--
-- Name: research_embedding_spaces research_embedding_spaces_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_embedding_spaces
    ADD CONSTRAINT research_embedding_spaces_pkey PRIMARY KEY (id);


--
-- Name: research_embeddings research_embeddings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_embeddings
    ADD CONSTRAINT research_embeddings_pkey PRIMARY KEY (id);


--
-- Name: research_ingestions research_ingestions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_ingestions
    ADD CONSTRAINT research_ingestions_pkey PRIMARY KEY (id);


--
-- Name: research_messages research_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_messages
    ADD CONSTRAINT research_messages_pkey PRIMARY KEY (id);


--
-- Name: research_model_attempts research_model_attempts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_model_attempts
    ADD CONSTRAINT research_model_attempts_pkey PRIMARY KEY (id);


--
-- Name: research_passages research_passages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_passages
    ADD CONSTRAINT research_passages_pkey PRIMARY KEY (id);


--
-- Name: research_retrievals research_retrievals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_retrievals
    ADD CONSTRAINT research_retrievals_pkey PRIMARY KEY (id);


--
-- Name: research_revisions research_revisions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_revisions
    ADD CONSTRAINT research_revisions_pkey PRIMARY KEY (id);


--
-- Name: research_tool_attempts research_tool_attempts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_tool_attempts
    ADD CONSTRAINT research_tool_attempts_pkey PRIMARY KEY (id);


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
-- Name: index_equibles_connections_on_id_and_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_equibles_connections_on_id_and_user_id ON public.equibles_connections USING btree (id, user_id);


--
-- Name: index_equibles_connections_on_quota_key_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_equibles_connections_on_quota_key_digest ON public.equibles_connections USING btree (quota_key_digest);


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
-- Name: index_research_agent_runs_on_conversation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_research_agent_runs_on_conversation_id ON public.research_agent_runs USING btree (conversation_id);


--
-- Name: index_research_agent_runs_on_id_and_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_research_agent_runs_on_id_and_user_id ON public.research_agent_runs USING btree (id, user_id);


--
-- Name: index_research_agent_runs_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_research_agent_runs_on_user_id ON public.research_agent_runs USING btree (user_id);


--
-- Name: index_research_agent_runs_on_user_id_and_request_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_research_agent_runs_on_user_id_and_request_key ON public.research_agent_runs USING btree (user_id, request_key);


--
-- Name: index_research_conversations_on_id_and_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_research_conversations_on_id_and_user_id ON public.research_conversations USING btree (id, user_id);


--
-- Name: index_research_conversations_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_research_conversations_on_user_id ON public.research_conversations USING btree (user_id);


--
-- Name: index_research_documents_on_id_and_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_research_documents_on_id_and_user_id ON public.research_documents USING btree (id, user_id);


--
-- Name: index_research_documents_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_research_documents_on_user_id ON public.research_documents USING btree (user_id);


--
-- Name: index_research_embedding_attempts_on_budget_date_and_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_research_embedding_attempts_on_budget_date_and_user_id ON public.research_embedding_attempts USING btree (budget_date, user_id);


--
-- Name: index_research_embedding_attempts_on_ingestion_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_research_embedding_attempts_on_ingestion_id ON public.research_embedding_attempts USING btree (ingestion_id);


--
-- Name: index_research_embedding_attempts_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_research_embedding_attempts_on_user_id ON public.research_embedding_attempts USING btree (user_id);


--
-- Name: index_research_embedding_spaces_on_id_and_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_research_embedding_spaces_on_id_and_user_id ON public.research_embedding_spaces USING btree (id, user_id);


--
-- Name: index_research_embedding_spaces_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_research_embedding_spaces_on_user_id ON public.research_embedding_spaces USING btree (user_id);


--
-- Name: index_research_embeddings_on_passage_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_research_embeddings_on_passage_id ON public.research_embeddings USING btree (passage_id);


--
-- Name: index_research_embeddings_on_space_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_research_embeddings_on_space_id ON public.research_embeddings USING btree (space_id);


--
-- Name: index_research_embeddings_on_space_id_and_passage_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_research_embeddings_on_space_id_and_passage_id ON public.research_embeddings USING btree (space_id, passage_id);


--
-- Name: index_research_embeddings_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_research_embeddings_on_user_id ON public.research_embeddings USING btree (user_id);


--
-- Name: index_research_ingestions_on_id_and_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_research_ingestions_on_id_and_user_id ON public.research_ingestions USING btree (id, user_id);


--
-- Name: index_research_ingestions_on_space_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_research_ingestions_on_space_id ON public.research_ingestions USING btree (space_id);


--
-- Name: index_research_ingestions_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_research_ingestions_on_user_id ON public.research_ingestions USING btree (user_id);


--
-- Name: index_research_ingestions_on_user_id_and_request_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_research_ingestions_on_user_id_and_request_key ON public.research_ingestions USING btree (user_id, request_key);


--
-- Name: index_research_messages_on_run_id_and_role; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_research_messages_on_run_id_and_role ON public.research_messages USING btree (run_id, role);


--
-- Name: index_research_messages_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_research_messages_on_user_id ON public.research_messages USING btree (user_id);


--
-- Name: index_research_model_attempts_on_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_research_model_attempts_on_run_id ON public.research_model_attempts USING btree (run_id);


--
-- Name: index_research_model_attempts_on_run_id_and_step; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_research_model_attempts_on_run_id_and_step ON public.research_model_attempts USING btree (run_id, step);


--
-- Name: index_research_model_attempts_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_research_model_attempts_on_user_id ON public.research_model_attempts USING btree (user_id);


--
-- Name: index_research_passages_on_revision_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_research_passages_on_revision_id ON public.research_passages USING btree (revision_id);


--
-- Name: index_research_passages_on_search_vector; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_research_passages_on_search_vector ON public.research_passages USING gin (search_vector);


--
-- Name: index_research_passages_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_research_passages_on_user_id ON public.research_passages USING btree (user_id);


--
-- Name: index_research_retrievals_on_agent_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_research_retrievals_on_agent_run_id ON public.research_retrievals USING btree (agent_run_id);


--
-- Name: index_research_retrievals_on_id_and_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_research_retrievals_on_id_and_user_id ON public.research_retrievals USING btree (id, user_id);


--
-- Name: index_research_retrievals_on_space_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_research_retrievals_on_space_id ON public.research_retrievals USING btree (space_id);


--
-- Name: index_research_retrievals_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_research_retrievals_on_user_id ON public.research_retrievals USING btree (user_id);


--
-- Name: index_research_retrievals_on_user_id_and_request_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_research_retrievals_on_user_id_and_request_key ON public.research_retrievals USING btree (user_id, request_key);


--
-- Name: index_research_revisions_on_document_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_research_revisions_on_document_id ON public.research_revisions USING btree (document_id);


--
-- Name: index_research_revisions_on_document_id_and_source_revision; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_research_revisions_on_document_id_and_source_revision ON public.research_revisions USING btree (document_id, source_revision);


--
-- Name: index_research_revisions_on_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_research_revisions_on_expires_at ON public.research_revisions USING btree (expires_at);


--
-- Name: index_research_revisions_on_id_and_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_research_revisions_on_id_and_user_id ON public.research_revisions USING btree (id, user_id);


--
-- Name: index_research_revisions_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_research_revisions_on_user_id ON public.research_revisions USING btree (user_id);


--
-- Name: index_research_revisions_on_user_id_and_known_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_research_revisions_on_user_id_and_known_at ON public.research_revisions USING btree (user_id, known_at);


--
-- Name: index_research_tool_attempts_on_run_id_and_call_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_research_tool_attempts_on_run_id_and_call_id ON public.research_tool_attempts USING btree (run_id, call_id);


--
-- Name: index_research_tool_attempts_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_research_tool_attempts_on_user_id ON public.research_tool_attempts USING btree (user_id);


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
-- Name: one_active_research_space; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX one_active_research_space ON public.research_embedding_spaces USING btree (user_id) WHERE ((state)::text = 'active'::text);


--
-- Name: one_active_sandbox_mandate; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX one_active_sandbox_mandate ON public.sandbox_mandates USING btree (sandbox_account_id) WHERE ((state)::text = 'active'::text);


--
-- Name: research_document_period; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX research_document_period ON public.research_documents USING btree (user_id, listing_identity, fiscal_year, fiscal_period);


--
-- Name: research_document_source; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX research_document_source ON public.research_documents USING btree (user_id, provider, source_kind, source_id);


--
-- Name: research_embedding_batch_attempt; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX research_embedding_batch_attempt ON public.research_embedding_attempts USING btree (ingestion_id, generation, batch_key);


--
-- Name: research_passage_identity; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX research_passage_identity ON public.research_passages USING btree (id, user_id, checksum, preprocessing_version, chunker_version);


--
-- Name: research_passage_position; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX research_passage_position ON public.research_passages USING btree (revision_id, preprocessing_version, chunker_version, "position");


--
-- Name: research_query_embedding_attempt; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX research_query_embedding_attempt ON public.research_embedding_attempts USING btree (retrieval_id, generation, batch_key);


--
-- Name: research_revision_document_identity; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX research_revision_document_identity ON public.research_revisions USING btree (id, document_id, user_id);


--
-- Name: research_run_conversation_owner; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX research_run_conversation_owner ON public.research_agent_runs USING btree (id, conversation_id, user_id);


--
-- Name: research_space_identity; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX research_space_identity ON public.research_embedding_spaces USING btree (id, user_id, preprocessing_version, chunker_version);


--
-- Name: research_space_version; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX research_space_version ON public.research_embedding_spaces USING btree (user_id, provider, model, model_version, preprocessing_version, chunker_version);


--
-- Name: research_agent_runs research_agent_identity_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER research_agent_identity_immutable BEFORE UPDATE ON public.research_agent_runs FOR EACH ROW EXECUTE FUNCTION public.research_agent_identity_guard();


--
-- Name: research_conversations research_conversation_identity; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER research_conversation_identity BEFORE UPDATE ON public.research_conversations FOR EACH ROW EXECUTE FUNCTION public.research_conversation_identity_guard();


--
-- Name: research_agent_runs research_durable_identity; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER research_durable_identity BEFORE UPDATE ON public.research_agent_runs FOR EACH ROW EXECUTE FUNCTION public.research_durable_identity_guard();


--
-- Name: research_retrievals research_retrieval_agent_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER research_retrieval_agent_immutable BEFORE UPDATE ON public.research_retrievals FOR EACH ROW EXECUTE FUNCTION public.research_retrieval_agent_guard();


--
-- Name: research_embedding_spaces research_space_identity_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER research_space_identity_immutable BEFORE UPDATE ON public.research_embedding_spaces FOR EACH ROW EXECUTE FUNCTION public.research_space_preserve_identity();


--
-- Name: sandbox_events sandbox_events_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sandbox_events_immutable BEFORE DELETE OR UPDATE ON public.sandbox_events FOR EACH ROW EXECUTE FUNCTION public.sandbox_reject_mutation();


--
-- Name: sandbox_orders sandbox_orders_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sandbox_orders_immutable BEFORE DELETE OR UPDATE ON public.sandbox_orders FOR EACH ROW EXECUTE FUNCTION public.sandbox_reject_mutation();


--
-- Name: research_revisions fk_rails_064a67cdb3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_revisions
    ADD CONSTRAINT fk_rails_064a67cdb3 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: research_embeddings fk_rails_09a47e97e3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_embeddings
    ADD CONSTRAINT fk_rails_09a47e97e3 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: user_stocks fk_rails_15a036aef2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_stocks
    ADD CONSTRAINT fk_rails_15a036aef2 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: research_tool_attempts fk_rails_1f38659908; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_tool_attempts
    ADD CONSTRAINT fk_rails_1f38659908 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: research_ingestions fk_rails_30463d7e2a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_ingestions
    ADD CONSTRAINT fk_rails_30463d7e2a FOREIGN KEY (document_id, user_id) REFERENCES public.research_documents(id, user_id);


--
-- Name: research_conversations fk_rails_30ee8495b5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_conversations
    ADD CONSTRAINT fk_rails_30ee8495b5 FOREIGN KEY (user_id) REFERENCES public.users(id);


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
-- Name: research_agent_runs fk_rails_4ae8e71229; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_agent_runs
    ADD CONSTRAINT fk_rails_4ae8e71229 FOREIGN KEY (conversation_id, user_id) REFERENCES public.research_conversations(id, user_id);


--
-- Name: research_ingestions fk_rails_50c0f35169; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_ingestions
    ADD CONSTRAINT fk_rails_50c0f35169 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: research_messages fk_rails_525b9d79f1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_messages
    ADD CONSTRAINT fk_rails_525b9d79f1 FOREIGN KEY (run_id, user_id) REFERENCES public.research_agent_runs(id, user_id);


--
-- Name: research_documents fk_rails_5b18552685; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_documents
    ADD CONSTRAINT fk_rails_5b18552685 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: user_stocks fk_rails_62699afff5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_stocks
    ADD CONSTRAINT fk_rails_62699afff5 FOREIGN KEY (stock_id) REFERENCES public.stocks(id);


--
-- Name: research_ingestions fk_rails_657d1d3b1a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_ingestions
    ADD CONSTRAINT fk_rails_657d1d3b1a FOREIGN KEY (space_id, user_id) REFERENCES public.research_embedding_spaces(id, user_id);


--
-- Name: research_messages fk_rails_67c8175ca5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_messages
    ADD CONSTRAINT fk_rails_67c8175ca5 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: research_embedding_spaces fk_rails_6fd2668bca; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_embedding_spaces
    ADD CONSTRAINT fk_rails_6fd2668bca FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: research_model_attempts fk_rails_794cc147dd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_model_attempts
    ADD CONSTRAINT fk_rails_794cc147dd FOREIGN KEY (run_id, user_id) REFERENCES public.research_agent_runs(id, user_id);


--
-- Name: research_embedding_attempts fk_rails_8be66e94f4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_embedding_attempts
    ADD CONSTRAINT fk_rails_8be66e94f4 FOREIGN KEY (ingestion_id, user_id) REFERENCES public.research_ingestions(id, user_id);


--
-- Name: research_embedding_attempts fk_rails_8c45d1a83a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_embedding_attempts
    ADD CONSTRAINT fk_rails_8c45d1a83a FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: research_documents fk_rails_926c3a1ab7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_documents
    ADD CONSTRAINT fk_rails_926c3a1ab7 FOREIGN KEY (current_revision_id, id, user_id) REFERENCES public.research_revisions(id, document_id, user_id);


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
-- Name: research_retrievals fk_rails_9c4c5cb670; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_retrievals
    ADD CONSTRAINT fk_rails_9c4c5cb670 FOREIGN KEY (space_id, user_id) REFERENCES public.research_embedding_spaces(id, user_id);


--
-- Name: research_passages fk_rails_a0d59c922d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_passages
    ADD CONSTRAINT fk_rails_a0d59c922d FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: research_agent_runs fk_rails_a4eac73836; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_agent_runs
    ADD CONSTRAINT fk_rails_a4eac73836 FOREIGN KEY (source_connection_id, user_id) REFERENCES public.equibles_connections(id, user_id);


--
-- Name: research_embeddings fk_rails_a7f4fe293b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_embeddings
    ADD CONSTRAINT fk_rails_a7f4fe293b FOREIGN KEY (space_id, user_id, preprocessing_version, chunker_version) REFERENCES public.research_embedding_spaces(id, user_id, preprocessing_version, chunker_version);


--
-- Name: research_model_attempts fk_rails_ab5485749e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_model_attempts
    ADD CONSTRAINT fk_rails_ab5485749e FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: sandbox_orders fk_rails_ad434e8514; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sandbox_orders
    ADD CONSTRAINT fk_rails_ad434e8514 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: research_messages fk_rails_b0020c36f9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_messages
    ADD CONSTRAINT fk_rails_b0020c36f9 FOREIGN KEY (conversation_id, user_id) REFERENCES public.research_conversations(id, user_id);


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
-- Name: research_agent_runs fk_rails_c4f08f3434; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_agent_runs
    ADD CONSTRAINT fk_rails_c4f08f3434 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: broker_connections fk_rails_ca90ba462e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.broker_connections
    ADD CONSTRAINT fk_rails_ca90ba462e FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: research_embeddings fk_rails_cc23758a1c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_embeddings
    ADD CONSTRAINT fk_rails_cc23758a1c FOREIGN KEY (passage_id, user_id, input_checksum, preprocessing_version, chunker_version) REFERENCES public.research_passages(id, user_id, checksum, preprocessing_version, chunker_version);


--
-- Name: research_retrievals fk_rails_cfce73375b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_retrievals
    ADD CONSTRAINT fk_rails_cfce73375b FOREIGN KEY (agent_run_id, user_id) REFERENCES public.research_agent_runs(id, user_id);


--
-- Name: research_passages fk_rails_d1d9e2d012; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_passages
    ADD CONSTRAINT fk_rails_d1d9e2d012 FOREIGN KEY (revision_id, user_id) REFERENCES public.research_revisions(id, user_id);


--
-- Name: friendships fk_rails_d78dc9c7fd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.friendships
    ADD CONSTRAINT fk_rails_d78dc9c7fd FOREIGN KEY (friend_id) REFERENCES public.users(id);


--
-- Name: research_revisions fk_rails_db04897481; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_revisions
    ADD CONSTRAINT fk_rails_db04897481 FOREIGN KEY (document_id, user_id) REFERENCES public.research_documents(id, user_id);


--
-- Name: friendships fk_rails_e3733b59b7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.friendships
    ADD CONSTRAINT fk_rails_e3733b59b7 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: research_embedding_attempts fk_rails_e476e973ba; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_embedding_attempts
    ADD CONSTRAINT fk_rails_e476e973ba FOREIGN KEY (retrieval_id, user_id) REFERENCES public.research_retrievals(id, user_id);


--
-- Name: research_tool_attempts fk_rails_ea1717f550; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_tool_attempts
    ADD CONSTRAINT fk_rails_ea1717f550 FOREIGN KEY (run_id, user_id) REFERENCES public.research_agent_runs(id, user_id);


--
-- Name: research_retrievals fk_rails_f6c6afe8e4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_retrievals
    ADD CONSTRAINT fk_rails_f6c6afe8e4 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: research_messages research_message_run_conversation; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.research_messages
    ADD CONSTRAINT research_message_run_conversation FOREIGN KEY (run_id, conversation_id, user_id) REFERENCES public.research_agent_runs(id, conversation_id, user_id);


--
-- PostgreSQL database dump complete
--

\unrestrict bj7YAv1GOF6VFyl4zZZNcllC5DUadEmRsUOZefgPEKtifO4PuE3kFBprDhIXNaL

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20261107100000'),
('20261107090100'),
('20261107090000'),
('20261107080100'),
('20261107080000'),
('20261107070000'),
('20261107060000'),
('20261105050000'),
('20261105043000'),
('20261105042000'),
('20240403103018'),
('20240403093954'),
('20240401185246'),
('20240328142412'),
('20240328083107');

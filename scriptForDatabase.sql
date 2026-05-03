--
-- PostgreSQL database dump
--

-- Dumped from database version 16.1
-- Dumped by pg_dump version 16.1

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
-- Name: topology; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA topology;


ALTER SCHEMA topology OWNER TO postgres;

--
-- Name: SCHEMA topology; Type: COMMENT; Schema: -; Owner: postgres
--

COMMENT ON SCHEMA topology IS 'PostGIS Topology schema';


--
-- Name: postgis; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;


--
-- Name: EXTENSION postgis; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION postgis IS 'PostGIS geometry and geography spatial types and functions';


--
-- Name: postgis_raster; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis_raster WITH SCHEMA public;


--
-- Name: EXTENSION postgis_raster; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION postgis_raster IS 'PostGIS raster types and functions';


--
-- Name: postgis_topology; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis_topology WITH SCHEMA topology;


--
-- Name: EXTENSION postgis_topology; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION postgis_topology IS 'PostGIS topology spatial types and functions';


--
-- Name: add_farmer_place(integer, character varying, character varying, numeric, jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.add_farmer_place(_supplier_id integer, _address character varying, _kadastrnumber character varying, _area numeric, _boundaries jsonb DEFAULT NULL::jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    _place_id INTEGER;
    _existing_place_id INTEGER;
    _result JSONB;
BEGIN
    -- Проверяем существование фермера
    IF NOT EXISTS (SELECT 1 FROM suppliers WHERE id = _supplier_id) THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Фермер с указанным ID не найден'
        );
    END IF;
    
    -- Проверяем, существует ли уже участок с таким кадастровым номером
    SELECT id INTO _existing_place_id
    FROM places
    WHERE kadastrnumber = _kadastrnumber;
    
    -- Если участок существует - используем его
    IF _existing_place_id IS NOT NULL THEN
        _place_id := _existing_place_id;
    ELSE
        -- Создаем новый участок
        INSERT INTO places (
            address,
            kadastrnumber,
            area,
            boundaries
        ) VALUES (
            _address,
            _kadastrnumber,
            _area,
            CASE 
                WHEN _boundaries IS NOT NULL 
                THEN ST_Transform(ST_GeomFromGeoJSON(_boundaries::TEXT), 3857)
                ELSE NULL
            END
        ) RETURNING id INTO _place_id;
    END IF;
    
    -- Проверяем, не привязан ли уже участок к этому фермеру
    IF EXISTS (
        SELECT 1 FROM supplierplaces 
        WHERE idsupplier = _supplier_id AND idplace = _place_id
    ) THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Этот участок уже привязан к данному фермеру'
        );
    END IF;
    
    -- Привязываем участок к фермеру
    INSERT INTO supplierplaces (
        idsupplier,
        idplace
    ) VALUES (
        _supplier_id,
        _place_id
    );
    
    RETURN jsonb_build_object(
        'success', true,
        'message', 'Участок успешно добавлен фермеру',
        'place_id', _place_id
    );
END;
$$;


ALTER FUNCTION public.add_farmer_place(_supplier_id integer, _address character varying, _kadastrnumber character varying, _area numeric, _boundaries jsonb) OWNER TO postgres;

--
-- Name: add_farmer_place(integer, character varying, character varying, numeric, double precision, double precision); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.add_farmer_place(_supplier_id integer, _address character varying, _kadastrnumber character varying, _area numeric, _center_lat double precision DEFAULT NULL::double precision, _center_lng double precision DEFAULT NULL::double precision) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    _place_id INTEGER;
    _existing_place_id INTEGER;
    _result JSONB;
    _boundaries geometry;
BEGIN
    -- Проверяем существование фермера
    IF NOT EXISTS (SELECT 1 FROM suppliers WHERE id = _supplier_id) THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Фермер с указанным ID не найден'
        );
    END IF;
    
    -- Проверяем, существует ли уже участок с таким кадастровым номером
    SELECT id INTO _existing_place_id
    FROM places
    WHERE kadastrnumber = _kadastrnumber;
    
    -- Если участок существует - используем его
    IF _existing_place_id IS NOT NULL THEN
        _place_id := _existing_place_id;
    ELSE
        -- Создаем полигон на основе центральных координат
        IF _center_lat IS NOT NULL AND _center_lng IS NOT NULL THEN
            -- Создаем небольшой полигон вокруг точки (примерно 200x200 метров)
            _boundaries := ST_MakeEnvelope(
                _center_lng - 0.002, _center_lat - 0.002,
                _center_lng + 0.002, _center_lat + 0.002,
                4326
            );
        ELSE
            -- Если координаты не указаны, создаем полигон по умолчанию в центре Москвы
            _boundaries := ST_MakeEnvelope(
                37.5, 55.5,
                37.6, 55.8,
                4326
            );
        END IF;
        
        -- Создаем новый участок
        INSERT INTO places (
            address,
            kadastrnumber,
            area,
            boundaries
        ) VALUES (
            _address,
            _kadastrnumber,
            _area,
            ST_Transform(_boundaries, 3857)  -- Конвертируем в проекцию 3857
        ) RETURNING id INTO _place_id;
    END IF;
    
    -- Проверяем, не привязан ли уже участок к этому фермеру
    IF EXISTS (
        SELECT 1 FROM supplierplaces 
        WHERE "idSupplier" = _supplier_id AND "idPlace" = _place_id
    ) THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Этот участок уже привязан к данному фермеру'
        );
    END IF;
    
    -- Привязываем участок к фермеру
    INSERT INTO supplierplaces (
        "idSupplier",
        "idPlace"
    ) VALUES (
        _supplier_id,
        _place_id
    );
    
    RETURN jsonb_build_object(
        'success', true,
        'message', 'Участок успешно добавлен фермеру',
        'place_id', _place_id
    );
END;
$$;


ALTER FUNCTION public.add_farmer_place(_supplier_id integer, _address character varying, _kadastrnumber character varying, _area numeric, _center_lat double precision, _center_lng double precision) OWNER TO postgres;

--
-- Name: add_farmer_product(integer, integer, integer, character varying, integer, integer, character varying, numeric, character varying, integer, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.add_farmer_product(_supplier_id integer, _place_id integer, _object_id integer, _product_name character varying, _wholepart integer DEFAULT 0, _copecks integer DEFAULT 0, _description character varying DEFAULT ''::character varying, _weight numeric DEFAULT NULL::numeric, _packaging character varying DEFAULT NULL::character varying, _dimension_id integer DEFAULT 3, _freshness_id integer DEFAULT 1, _quantity integer DEFAULT 1) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    _supplier_place_id INTEGER;
    _product_id INTEGER;
    _result JSONB;
BEGIN
    -- Проверяем, что участок принадлежит фермеру
    SELECT id INTO _supplier_place_id
    FROM "supplierPlaces"
    WHERE "idSupplier" = _supplier_id AND "idPlace" = _place_id;
    
    IF _supplier_place_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Участок не принадлежит указанному фермеру'
        );
    END IF;
    
    -- Создаем продукт
    INSERT INTO products (
        name,
        "idObject"
    ) VALUES (
        _product_name,
        _object_id
    ) RETURNING id INTO _product_id;
    
    -- Создаем копию продукта
    INSERT INTO productcopies (
        idproduct,
        discount,
        copecks,
        wholepart,
        decsription,
        isactual,
        rating,
        iddimension,
        weight,
        packaging,
        releasedate,
        idfreshness
    ) VALUES (
        _product_id,
        0,
        _copecks,
        _wholepart,
        _description,
        true,
        0.0,
        _dimension_id,
        _weight,
        _packaging,
        NOW(),
        _freshness_id
    );
    
    -- Связываем продукт с участком
    INSERT INTO supplierplacesproducts (
        idsupplierplace,
        idproduct
    ) VALUES (
        _supplier_place_id,
        _product_id
    );
    
    -- Добавляем категорию продукта (по умолчанию - овощи)
    INSERT INTO productcategories (
        idproduct,
        idcategory
    ) VALUES (
        _product_id,
        2 -- по умолчанию овощи
    );
    
    RETURN jsonb_build_object(
        'success', true,
        'message', 'Продукт успешно добавлен',
        'product_id', _product_id
    );
END;
$$;


ALTER FUNCTION public.add_farmer_product(_supplier_id integer, _place_id integer, _object_id integer, _product_name character varying, _wholepart integer, _copecks integer, _description character varying, _weight numeric, _packaging character varying, _dimension_id integer, _freshness_id integer, _quantity integer) OWNER TO postgres;

--
-- Name: calculate_farmer_rating(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.calculate_farmer_rating(p_supplier_id integer) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_avg_rating NUMERIC(3,1);
    v_product_count INTEGER;
    v_weighted_rating NUMERIC(3,1);
BEGIN
    -- Простое среднее арифметическое
    SELECT 
        AVG(pc.rating) as avg_rating,
        COUNT(pc.id) as product_count
    INTO v_avg_rating, v_product_count
    FROM "supplierPlaces" sp
    JOIN "supplierPlacesProducts" spp ON sp.id = spp.idsupplierplace
    JOIN products p ON spp.idproduct = p.id
    JOIN productcopies pc ON p.id = pc.idproduct
    WHERE sp.idsupplier = p_supplier_id
    AND pc.rating > 0;
    
    -- Если есть продукты, возвращаем среднее, иначе 0
    IF v_product_count > 0 THEN
        RETURN ROUND(v_avg_rating::NUMERIC, 1);
    ELSE
        RETURN 0.0;
    END IF;
END;
$$;


ALTER FUNCTION public.calculate_farmer_rating(p_supplier_id integer) OWNER TO postgres;

--
-- Name: create_farmer(character varying, character varying, character varying, character varying, text, character varying, character varying, numeric, jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.create_farmer(_username character varying, _email character varying, _password character varying, _farmer_name character varying, _description text DEFAULT ''::text, _place_address character varying DEFAULT NULL::character varying, _place_kadastr character varying DEFAULT NULL::character varying, _place_area numeric DEFAULT NULL::numeric, _place_boundaries jsonb DEFAULT NULL::jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    _user_id INTEGER;
    _supplier_id INTEGER;
    _place_id INTEGER;
    _result JSONB;
BEGIN
    -- Начинаем транзакцию
    BEGIN
        -- 1. Создаем пользователя
        INSERT INTO users (
            username, 
            email, 
            password, 
            roleid
        ) VALUES (
            _username,
            _email,
            _password,
            2 -- роль фермера
        ) RETURNING id INTO _user_id;
        
        -- 2. Создаем запись в suppliers
        INSERT INTO suppliers (
            name,
            userid
        ) VALUES (
            _farmer_name,
            _user_id
        ) RETURNING id INTO _supplier_id;
        
        -- 3. Создаем запись в suppliercopies
        INSERT INTO suppliercopies (
            idsupplier,
            description,
            rating,
            "isActual"
        ) VALUES (
            _supplier_id,
            _description,
            0.0, -- начальный рейтинг
            true
        );
        
        -- 4. Если передан адрес участка - создаем участок
        IF _place_address IS NOT NULL AND _place_kadastr IS NOT NULL THEN
            -- Проверяем, существует ли уже участок с таким кадастровым номером
            SELECT id INTO _place_id
            FROM places
            WHERE kadastrnumber = _place_kadastr;
            
            -- Если участок не существует - создаем новый
            IF _place_id IS NULL THEN
                INSERT INTO places (
                    address,
                    kadastrnumber,
                    area,
                    boundaries
                ) VALUES (
                    _place_address,
                    _place_kadastr,
                    _place_area,
                    CASE 
                        WHEN _place_boundaries IS NOT NULL 
                        THEN ST_Transform(ST_GeomFromGeoJSON(_place_boundaries::TEXT), 3857)
                        ELSE NULL
                    END
                ) RETURNING id INTO _place_id;
            END IF;
            
            -- Связываем участок с фермером
            INSERT INTO supplierplaces (
                idsupplier,
                idplace
            ) VALUES (
                _supplier_id,
                _place_id
            );
        END IF;
        
        -- Формируем результат
        _result := jsonb_build_object(
            'success', true,
            'message', 'Фермер успешно создан',
            'user_id', _user_id,
            'supplier_id', _supplier_id,
            'place_id', _place_id
        );
        
        RETURN _result;
        
    EXCEPTION 
        WHEN unique_violation THEN
            -- Обработка ошибок уникальности
            IF SQLERRM LIKE '%users_username_key%' THEN
                RETURN jsonb_build_object(
                    'success', false,
                    'message', 'Пользователь с таким именем уже существует'
                );
            ELSIF SQLERRM LIKE '%users_email_key%' THEN
                RETURN jsonb_build_object(
                    'success', false,
                    'message', 'Пользователь с таким email уже существует'
                );
            ELSE
                RETURN jsonb_build_object(
                    'success', false,
                    'message', SQLERRM
                );
            END IF;
        WHEN OTHERS THEN
            RETURN jsonb_build_object(
                'success', false,
                'message', SQLERRM
            );
    END;
END;
$$;


ALTER FUNCTION public.create_farmer(_username character varying, _email character varying, _password character varying, _farmer_name character varying, _description text, _place_address character varying, _place_kadastr character varying, _place_area numeric, _place_boundaries jsonb) OWNER TO postgres;

--
-- Name: create_farmer(character varying, character varying, character varying, character varying, text, character varying, character varying, numeric, double precision, double precision); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.create_farmer(_username character varying, _email character varying, _password character varying, _farmer_name character varying, _description text DEFAULT ''::text, _place_address character varying DEFAULT NULL::character varying, _place_kadastr character varying DEFAULT NULL::character varying, _place_area numeric DEFAULT NULL::numeric, _center_lat double precision DEFAULT NULL::double precision, _center_lng double precision DEFAULT NULL::double precision) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    _user_id INTEGER;
    _supplier_id INTEGER;
    _place_id INTEGER;
    _result JSONB;
BEGIN
    -- Начинаем транзакцию
    BEGIN
        -- 1. Создаем пользователя
        INSERT INTO users (
            username, 
            email, 
            password, 
            roleid
        ) VALUES (
            _username,
            _email,
            _password,
            2 -- роль фермера
        ) RETURNING id INTO _user_id;
        
        -- 2. Создаем запись в suppliers
        INSERT INTO suppliers (
            name,
            userid
        ) VALUES (
            _farmer_name,
            _user_id
        ) RETURNING id INTO _supplier_id;
        
        -- 3. Создаем запись в suppliercopies
        INSERT INTO suppliercopies (
            idsupplier,
            description,
            rating,
            "isActual"
        ) VALUES (
            _supplier_id,
            _description,
            0.0, -- начальный рейтинг
            true
        );
        
        -- 4. Если передан адрес участка - создаем участок
        IF _place_address IS NOT NULL AND _place_kadastr IS NOT NULL THEN
            -- Используем исправленную функцию add_farmer_place
            _result := add_farmer_place(
                _supplier_id,
                _place_address,
                _place_kadastr,
                COALESCE(_place_area, 1000),
                _center_lat,
                _center_lng
            );
            
            IF (_result->>'success')::BOOLEAN THEN
                _place_id := (_result->>'place_id')::INTEGER;
            END IF;
        END IF;
        
        -- Формируем результат
        _result := jsonb_build_object(
            'success', true,
            'message', 'Фермер успешно создан',
            'user_id', _user_id,
            'supplier_id', _supplier_id,
            'place_id', _place_id
        );
        
        RETURN _result;
        
    EXCEPTION 
        WHEN unique_violation THEN
            -- Обработка ошибок уникальности
            IF SQLERRM LIKE '%users_username_key%' THEN
                RETURN jsonb_build_object(
                    'success', false,
                    'message', 'Пользователь с таким именем уже существует'
                );
            ELSIF SQLERRM LIKE '%users_email_key%' THEN
                RETURN jsonb_build_object(
                    'success', false,
                    'message', 'Пользователь с таким email уже существует'
                );
            ELSE
                RETURN jsonb_build_object(
                    'success', false,
                    'message', SQLERRM
                );
            END IF;
        WHEN OTHERS THEN
            RETURN jsonb_build_object(
                'success', false,
                'message', SQLERRM
            );
    END;
END;
$$;


ALTER FUNCTION public.create_farmer(_username character varying, _email character varying, _password character varying, _farmer_name character varying, _description text, _place_address character varying, _place_kadastr character varying, _place_area numeric, _center_lat double precision, _center_lng double precision) OWNER TO postgres;

--
-- Name: create_farmer_product(integer, integer, integer, character varying, integer, integer, character varying, numeric, character varying, integer, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.create_farmer_product(_farmer_id integer, _culture_id integer, _variety_id integer, _product_name character varying, _wholepart integer DEFAULT 0, _copecks integer DEFAULT 0, _description character varying DEFAULT ''::character varying, _weight numeric DEFAULT NULL::numeric, _packaging character varying DEFAULT NULL::character varying, _dimension_id integer DEFAULT 3, _place_id integer DEFAULT NULL::integer, _quantity integer DEFAULT 1) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    _object_id INTEGER;
    _product_id INTEGER;
    _supplier_place_id INTEGER;
    _result JSONB;
BEGIN
    -- 1. Получаем object_id из culture_id
    SELECT id INTO _object_id 
    FROM public."namesObjects" 
    WHERE id = _culture_id
	AND idvariety = _variety_id;
    
    IF _object_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false, 
            'message', 'Культура не найдена'
        );
    END IF;

    -- 2. Создаем продукт
    INSERT INTO products (name, idobject)
    VALUES (_product_name, _object_id)
    RETURNING id INTO _product_id;

    -- 3. Создаем копию продукта
    INSERT INTO productcopies (
        idproduct, 
        discount, 
        copecks, 
        wholepart, 
        decsription, 
        isactual, 
        iddimension, 
        weight, 
        packaging,
        rating,
        releasedate
    ) VALUES (
        _product_id,
        0,
        COALESCE(_copecks, 0),
        COALESCE(_wholepart, 0),
        _description,
        true,
        _dimension_id,
        _weight,
        _packaging,
        0.0,
        NOW()
    );

    -- 4. Если указан участок - связываем
    IF _place_id IS NOT NULL THEN
        -- Проверяем связь фермер-участок
        SELECT id INTO _supplier_place_id
        FROM supplierplaces
        WHERE idsupplier = _farmer_id AND idplace = _place_id;
        
        IF _supplier_place_id IS NULL THEN
            INSERT INTO supplierplaces (idsupplier, idplace)
            VALUES (_farmer_id, _place_id)
            RETURNING id INTO _supplier_place_id;
        END IF;
        
        -- Связываем продукт с участком
        INSERT INTO supplierplacesproducts (idsupplierplace, idproduct)
        VALUES (_supplier_place_id, _product_id);
    END IF;

    -- 5. Возвращаем результат
    _result := jsonb_build_object(
        'success', true,
        'message', 'Товар успешно создан',
        'product_id', _product_id,
        'culture_id', _culture_id,
        'variety_id', _variety_id,
        'product_name', _product_name
    );

    RETURN _result;

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false,
        'message', SQLERRM,
        'detail', SQLSTATE
    );
END;
$$;


ALTER FUNCTION public.create_farmer_product(_farmer_id integer, _culture_id integer, _variety_id integer, _product_name character varying, _wholepart integer, _copecks integer, _description character varying, _weight numeric, _packaging character varying, _dimension_id integer, _place_id integer, _quantity integer) OWNER TO postgres;

--
-- Name: createuserwithrolesupplier(text, text, text, text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.createuserwithrolesupplier(_name text, _description text, _username text, _email text, _password text) RETURNS integer
    LANGUAGE plpgsql
    AS $$ 
	DECLARE vId INTEGER;
	BEGIN
	INSERT INTO users(username, email, password, idRole) VALUES (_username, _email, _password, 2) RETURNING id INTO vId;
	INSERT INTO suppliers(name, idUser) VALUES (_name, 	vId) RETURNING id INTO vId;
	INSERT INTO supplierCopies (idSupplier, description) VALUES (vId,_description);
	RETURN vId;
	END;
	$$;


ALTER FUNCTION public.createuserwithrolesupplier(_name text, _description text, _username text, _email text, _password text) OWNER TO postgres;

--
-- Name: get_varieties_by_name(character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_varieties_by_name(p_name character varying) RETURNS TABLE(variety_id integer, names_object_id integer, variety_name character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT 
        v.id AS variety_id,
        no.id AS names_object_id, 
        v.name AS variety_name    
    FROM public."namesObjects" no
    JOIN public.varieties v ON v.id = no.idvariety
    WHERE no.name ILIKE p_name
      AND no.idvariety IS NOT NULL
    ORDER BY v.name;
END;
$$;


ALTER FUNCTION public.get_varieties_by_name(p_name character varying) OWNER TO postgres;

--
-- Name: set_updated_at(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.set_updated_at() OWNER TO postgres;

--
-- Name: update_farmer_rating(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_farmer_rating() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_supplier_id INTEGER;
    v_new_rating NUMERIC(3,1);
BEGIN
    -- Находим фермера через связи
    SELECT DISTINCT sp.idsupplier INTO v_supplier_id
    FROM supplierplacesproducts spp
    JOIN supplierplaces sp ON spp.idsupplierplace = sp.id
    WHERE spp.idproduct = NEW.idproduct;
    
    IF v_supplier_id IS NOT NULL THEN
        -- Вычисляем новый рейтинг
        v_new_rating := calculate_farmer_rating(v_supplier_id);
        
        -- Обновляем рейтинг в suppliercopies
        UPDATE suppliercopies
        SET rating = v_new_rating
        WHERE idsupplier = v_supplier_id;
    END IF;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_farmer_rating() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: auctionBids; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."auctionBids" (
    id integer NOT NULL,
    "idAuction" integer,
    "idUser" integer,
    "bidAmountWhole" integer NOT NULL,
    "bidAmountCopecks" integer NOT NULL,
    "bidTime" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    "isWinning" boolean DEFAULT false
);


ALTER TABLE public."auctionBids" OWNER TO postgres;

--
-- Name: auctionHistory; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."auctionHistory" (
    id integer NOT NULL,
    "idAuction" integer,
    "changedAt" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    "changedBy" integer,
    "isActive" boolean DEFAULT true,
    status character varying(20) DEFAULT 'draft'::character varying,
    reason text
);


ALTER TABLE public."auctionHistory" OWNER TO postgres;

--
-- Name: auctionbids_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.auctionbids_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.auctionbids_id_seq OWNER TO postgres;

--
-- Name: auctionbids_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.auctionbids_id_seq OWNED BY public."auctionBids".id;


--
-- Name: auctionhistory_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.auctionhistory_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.auctionhistory_id_seq OWNER TO postgres;

--
-- Name: auctionhistory_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.auctionhistory_id_seq OWNED BY public."auctionHistory".id;


--
-- Name: auctions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.auctions (
    id integer NOT NULL,
    "idSupplier" integer,
    "lotNumber" character varying(20) NOT NULL,
    title character varying(255) NOT NULL,
    description text,
    "idProduct" integer,
    "startPrice" numeric(10,2),
    "minStep" numeric(10,2),
    "buyNowPrice" numeric(10,2),
    characteristics jsonb,
    "deliveryRegion" character varying(255),
    "idPlace" integer,
    "startTime" timestamp without time zone NOT NULL,
    "endTime" timestamp without time zone NOT NULL,
    "createdAt" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    vatincluded boolean DEFAULT false
);


ALTER TABLE public.auctions OWNER TO postgres;

--
-- Name: auctions_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.auctions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.auctions_id_seq OWNER TO postgres;

--
-- Name: auctions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.auctions_id_seq OWNED BY public.auctions.id;


--
-- Name: buyerRequests; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."buyerRequests" (
    id bigint NOT NULL,
    "idUser" bigint NOT NULL,
    "productName" character varying(255) NOT NULL,
    "idObject" bigint NOT NULL,
    "quantityNeeded" numeric(12,2) DEFAULT 1 NOT NULL,
    "maxPriceWhole" integer DEFAULT 0 NOT NULL,
    "maxPriceCopecks" integer DEFAULT 0 NOT NULL,
    "expiresAt" timestamp without time zone NOT NULL,
    status character varying(20) DEFAULT 'active'::character varying NOT NULL,
    "createdAt" timestamp without time zone DEFAULT now() NOT NULL,
    "updatedAt" timestamp without time zone DEFAULT now() NOT NULL,
    CONSTRAINT buyer_requests_price_copecks_chk CHECK ((("maxPriceCopecks" >= 0) AND ("maxPriceCopecks" <= 99))),
    CONSTRAINT buyer_requests_price_whole_chk CHECK (("maxPriceWhole" >= 0)),
    CONSTRAINT buyer_requests_quantity_chk CHECK (("quantityNeeded" > (0)::numeric)),
    CONSTRAINT buyer_requests_status_chk CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'fulfilled'::character varying, 'expired'::character varying, 'cancelled'::character varying])::text[])))
);


ALTER TABLE public."buyerRequests" OWNER TO postgres;

--
-- Name: buyer_requests_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.buyer_requests_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.buyer_requests_id_seq OWNER TO postgres;

--
-- Name: buyer_requests_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.buyer_requests_id_seq OWNED BY public."buyerRequests".id;


--
-- Name: certificateRequests; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."certificateRequests" (
    id integer NOT NULL,
    "idSupplier" integer NOT NULL,
    "IdCertificateType" integer NOT NULL,
    "requestDate" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    status character varying(20) DEFAULT 'pending'::character varying,
    "adminComment" text,
    "processedBy" integer,
    "processedAt" timestamp without time zone
);


ALTER TABLE public."certificateRequests" OWNER TO postgres;

--
-- Name: certificateTypes; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."certificateTypes" (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    description text,
    icon character varying(50),
    "requiredDocuments" jsonb,
    "validityDays" integer DEFAULT 365,
    "isActive" boolean DEFAULT true,
    "createdAt" timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public."certificateTypes" OWNER TO postgres;

--
-- Name: certificate_requests_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.certificate_requests_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.certificate_requests_id_seq OWNER TO postgres;

--
-- Name: certificate_requests_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.certificate_requests_id_seq OWNED BY public."certificateRequests".id;


--
-- Name: certificate_types_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.certificate_types_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.certificate_types_id_seq OWNER TO postgres;

--
-- Name: certificate_types_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.certificate_types_id_seq OWNED BY public."certificateTypes".id;


--
-- Name: countries; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.countries (
    id integer NOT NULL,
    name character varying(255)
);


ALTER TABLE public.countries OWNER TO postgres;

--
-- Name: cultureRipenessDeliveryRules; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."cultureRipenessDeliveryRules" (
    id integer NOT NULL,
    idNameObject integer NOT NULL,
    hoursUnripeToAlmostRipe numeric(10,2) NOT NULL,
    hoursAlmostRipeToRipe numeric(10,2) NOT NULL,
    hoursRipeToSpoiled numeric(10,2) NOT NULL,
    minSafeTempC numeric(5,2),
    maxSafeTempc numeric(5,2),
    comment text,
    createdAt timestamp without time zone DEFAULT now(),
    updatedAt timestamp without time zone DEFAULT now()
);


ALTER TABLE public."cultureRipenessDeliveryRules" OWNER TO postgres;

--
-- Name: cultureripenessdeliveryrules_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.cultureripenessdeliveryrules_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.cultureripenessdeliveryrules_id_seq OWNER TO postgres;

--
-- Name: cultureripenessdeliveryrules_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.cultureripenessdeliveryrules_id_seq OWNED BY public."cultureRipenessDeliveryRules".id;


--
-- Name: customers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.customers (
    id integer NOT NULL,
    name character varying(255),
    "idUser" integer NOT NULL,
    "deliveryAddress" character varying(255)
);


ALTER TABLE public.customers OWNER TO postgres;

--
-- Name: customers_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.customers_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.customers_id_seq OWNER TO postgres;

--
-- Name: customers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.customers_id_seq OWNED BY public.customers.id;


--
-- Name: dietTableProducts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."dietTableProducts" (
    id integer NOT NULL,
    "idTabel" integer,
    "idProduct" integer,
    "idVariety" integer,
    "createdAt" timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public."dietTableProducts" OWNER TO postgres;

--
-- Name: dietTables; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."dietTables" (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    "createdAt" timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public."dietTables" OWNER TO postgres;

--
-- Name: diet_table_products_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.diet_table_products_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.diet_table_products_id_seq OWNER TO postgres;

--
-- Name: diet_table_products_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.diet_table_products_id_seq OWNED BY public."dietTableProducts".id;


--
-- Name: diet_tables_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.diet_tables_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.diet_tables_id_seq OWNER TO postgres;

--
-- Name: diet_tables_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.diet_tables_id_seq OWNED BY public."dietTables".id;


--
-- Name: farmerCertificates; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."farmerCertificates" (
    id integer NOT NULL,
    "idSupplier" integer NOT NULL,
    "IdCertificateType" integer NOT NULL,
    "certificateNumber" character varying(100),
    "issuedBy" character varying(255),
    "issueDate" date,
    "expiryDate" date,
    status character varying(20) DEFAULT 'pending'::character varying,
    "documentPath" text,
    "documentName" character varying(255),
    "documentType" character varying(50),
    "verificationComment" text,
    "createdAt" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    "verifiedBy" integer,
    "verifiedAt" timestamp without time zone
);


ALTER TABLE public."farmerCertificates" OWNER TO postgres;

--
-- Name: farmerSubscriptions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."farmerSubscriptions" (
    id integer NOT NULL,
    "idCustomer" integer NOT NULL,
    "idSupplier" integer NOT NULL,
    "createdAt" timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public."farmerSubscriptions" OWNER TO postgres;

--
-- Name: farmer_certificates_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.farmer_certificates_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.farmer_certificates_id_seq OWNER TO postgres;

--
-- Name: farmer_certificates_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.farmer_certificates_id_seq OWNED BY public."farmerCertificates".id;


--
-- Name: farmer_subscriptions_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.farmer_subscriptions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.farmer_subscriptions_id_seq OWNER TO postgres;

--
-- Name: farmer_subscriptions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.farmer_subscriptions_id_seq OWNED BY public."farmerSubscriptions".id;


--
-- Name: freshness; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.freshness (
    id integer NOT NULL,
    name character varying(255)
);


ALTER TABLE public.freshness OWNER TO postgres;

--
-- Name: freshness_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.freshness_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.freshness_id_seq OWNER TO postgres;

--
-- Name: freshness_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.freshness_id_seq OWNED BY public.freshness.id;


--
-- Name: locationProduct; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."locationProduct" (
    id integer NOT NULL,
    name character varying(255)
);


ALTER TABLE public."locationProduct" OWNER TO postgres;

--
-- Name: locationproduct_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.locationproduct_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.locationproduct_id_seq OWNER TO postgres;

--
-- Name: locationproduct_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.locationproduct_id_seq OWNED BY public."locationProduct".id;


--
-- Name: namesObjects; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."namesObjects" (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    "idVariety" integer
);


ALTER TABLE public."namesObjects" OWNER TO postgres;

--
-- Name: namesObjects_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public."namesObjects_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public."namesObjects_id_seq" OWNER TO postgres;

--
-- Name: namesObjects_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public."namesObjects_id_seq" OWNED BY public."namesObjects".id;


--
-- Name: places; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.places (
    id integer NOT NULL,
    address character varying(255),
    "kadastrNumber" character varying(64),
    area numeric(10,2),
    boundaries public.geometry(Polygon,3857),
    "imageUrl" text,
    "idCountry" integer
);


ALTER TABLE public.places OWNER TO postgres;

--
-- Name: places_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.places_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.places_id_seq OWNER TO postgres;

--
-- Name: places_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.places_id_seq OWNED BY public.places.id;


--
-- Name: productCategories; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."productCategories" (
    id integer NOT NULL,
    name character varying(255),
    "idProduct" integer,
    "idCategory" integer
);


ALTER TABLE public."productCategories" OWNER TO postgres;

--
-- Name: productCategory; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."productCategory" (
    id integer NOT NULL,
    name character varying(512) NOT NULL
);


ALTER TABLE public."productCategory" OWNER TO postgres;

--
-- Name: productCopies; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."productCopies" (
    id integer NOT NULL,
    "idProduct" integer NOT NULL,
    discount integer,
    copecks integer,
    "wholePart" integer,
    decsription character varying(2048),
    "isActual" boolean,
    rating numeric(2,1),
    "idDimension" integer NOT NULL,
    weight numeric(10,2),
    proteines numeric(10,1),
    lipides numeric(10,1),
    glucides numeric(10,1),
    calories numeric(10,1),
    joules numeric(10,1),
    "expirationDate" integer,
    "releaseDate" timestamp without time zone,
    packaging character varying(255),
    "placeOfOrigin" character varying(255),
    "idLocationProduct" integer,
    "idFreshness" integer
);


ALTER TABLE public."productCopies" OWNER TO postgres;

--
-- Name: productDimensions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."productDimensions" (
    id integer NOT NULL,
    name character varying(255) NOT NULL
);


ALTER TABLE public."productDimensions" OWNER TO postgres;

--
-- Name: productcategories_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.productcategories_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.productcategories_id_seq OWNER TO postgres;

--
-- Name: productcategories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.productcategories_id_seq OWNED BY public."productCategories".id;


--
-- Name: productcategory_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.productcategory_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.productcategory_id_seq OWNER TO postgres;

--
-- Name: productcategory_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.productcategory_id_seq OWNED BY public."productCategory".id;


--
-- Name: productcopies_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.productcopies_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.productcopies_id_seq OWNER TO postgres;

--
-- Name: productcopies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.productcopies_id_seq OWNED BY public."productCopies".id;


--
-- Name: productdimensions_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.productdimensions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.productdimensions_id_seq OWNER TO postgres;

--
-- Name: productdimensions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.productdimensions_id_seq OWNED BY public."productDimensions".id;


--
-- Name: productonSupplierPlace; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."productonSupplierPlace" (
    id integer NOT NULL,
    "idSupplierPlace" integer NOT NULL,
    "idProductCategory" integer NOT NULL
);


ALTER TABLE public."productonSupplierPlace" OWNER TO postgres;

--
-- Name: productonsupplierplace_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.productonsupplierplace_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.productonsupplierplace_id_seq OWNER TO postgres;

--
-- Name: productonsupplierplace_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.productonsupplierplace_id_seq OWNED BY public."productonSupplierPlace".id;


--
-- Name: products; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.products (
    id integer NOT NULL,
    name character varying(512),
    "idObject" integer NOT NULL,
    "imagePath" text
);


ALTER TABLE public.products OWNER TO postgres;

--
-- Name: products_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.products_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.products_id_seq OWNER TO postgres;

--
-- Name: products_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.products_id_seq OWNED BY public.products.id;


--
-- Name: purchases; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.purchases (
    id integer NOT NULL,
    "idProduct" integer,
    "idSupplier" integer,
    "idCustomer" integer,
    "idPlace" integer,
    quantity integer DEFAULT 1,
    status character varying(20) DEFAULT 'pending'::character varying,
    "paymentMethod" character varying(50),
    "deliveryAddress" text,
    "contactPhone" character varying(20),
    "contactEmail" character varying(100),
    comment text,
    "createdAt" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" timestamp without time zone,
    "completedAt" timestamp without time zone
);


ALTER TABLE public.purchases OWNER TO postgres;

--
-- Name: purchases_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.purchases_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.purchases_id_seq OWNER TO postgres;

--
-- Name: purchases_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.purchases_id_seq OWNED BY public.purchases.id;


--
-- Name: requestResponses; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."requestResponses" (
    id bigint NOT NULL,
    "idRequest" bigint NOT NULL,
    "idSupplier" bigint NOT NULL,
    "offeredPriceWhole" integer DEFAULT 0 NOT NULL,
    "offeredPriceCopecks" integer DEFAULT 0 NOT NULL,
    "estimatedQuantity" numeric(12,2) DEFAULT 1 NOT NULL,
    "deliveryDays" integer DEFAULT 1 NOT NULL,
    "responseText" text,
    status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    "createdAt" timestamp without time zone DEFAULT now() NOT NULL,
    "updatedAt" timestamp without time zone DEFAULT now() NOT NULL,
    CONSTRAINT request_responses_delivery_days_chk CHECK (("deliveryDays" >= 0)),
    CONSTRAINT request_responses_price_copecks_chk CHECK ((("offeredPriceCopecks" >= 0) AND ("offeredPriceCopecks" <= 99))),
    CONSTRAINT request_responses_price_whole_chk CHECK (("offeredPriceWhole" >= 0)),
    CONSTRAINT request_responses_quantity_chk CHECK (("estimatedQuantity" > (0)::numeric)),
    CONSTRAINT request_responses_status_chk CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'accepted'::character varying, 'rejected'::character varying])::text[])))
);


ALTER TABLE public."requestResponses" OWNER TO postgres;

--
-- Name: request_responses_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.request_responses_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.request_responses_id_seq OWNER TO postgres;

--
-- Name: request_responses_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.request_responses_id_seq OWNED BY public."requestResponses".id;


--
-- Name: roles; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.roles (
    id integer NOT NULL,
    name character varying(255) NOT NULL
);


ALTER TABLE public.roles OWNER TO postgres;

--
-- Name: roles_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.roles_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.roles_id_seq OWNER TO postgres;

--
-- Name: roles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.roles_id_seq OWNED BY public.roles.id;


--
-- Name: supplierCategories; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."supplierCategories" (
    id integer NOT NULL,
    name character varying(255) NOT NULL
);


ALTER TABLE public."supplierCategories" OWNER TO postgres;

--
-- Name: supplierCopies; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."supplierCopies" (
    id integer NOT NULL,
    "idSupplier" integer,
    rating numeric(2,1),
    description character varying(2048),
    "isActual" boolean DEFAULT true
);


ALTER TABLE public."supplierCopies" OWNER TO postgres;

--
-- Name: supplierPlaces; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."supplierPlaces" (
    id integer NOT NULL,
    "idSupplier" integer NOT NULL,
    "idPlace" integer NOT NULL
);


ALTER TABLE public."supplierPlaces" OWNER TO postgres;

--
-- Name: supplierPlacesProducts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."supplierPlacesProducts" (
    id integer NOT NULL,
    "idSupplierPlace" integer NOT NULL,
    "idProduct" integer NOT NULL
);


ALTER TABLE public."supplierPlacesProducts" OWNER TO postgres;

--
-- Name: suppliercategories_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.suppliercategories_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.suppliercategories_id_seq OWNER TO postgres;

--
-- Name: suppliercategories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.suppliercategories_id_seq OWNED BY public."supplierCategories".id;


--
-- Name: suppliercopy_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.suppliercopy_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.suppliercopy_id_seq OWNER TO postgres;

--
-- Name: suppliercopy_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.suppliercopy_id_seq OWNED BY public."supplierCopies".id;


--
-- Name: supplierplaces_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.supplierplaces_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.supplierplaces_id_seq OWNER TO postgres;

--
-- Name: supplierplaces_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.supplierplaces_id_seq OWNED BY public."supplierPlaces".id;


--
-- Name: supplierplacesproducts_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.supplierplacesproducts_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.supplierplacesproducts_id_seq OWNER TO postgres;

--
-- Name: supplierplacesproducts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.supplierplacesproducts_id_seq OWNED BY public."supplierPlacesProducts".id;


--
-- Name: suppliers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.suppliers (
    id integer NOT NULL,
    name character varying(255),
    "idUser" integer,
    "showCertificates" boolean DEFAULT true,
    "avatarUrl" text
);


ALTER TABLE public.suppliers OWNER TO postgres;

--
-- Name: suppliers_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.suppliers_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.suppliers_id_seq OWNER TO postgres;

--
-- Name: suppliers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.suppliers_id_seq OWNED BY public.suppliers.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.users (
    id integer NOT NULL,
    "userName" character varying(50) NOT NULL,
    email character varying(100) NOT NULL,
    password character varying(255) NOT NULL,
    "idRole" integer NOT NULL
);


ALTER TABLE public.users OWNER TO postgres;

--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.users_id_seq OWNER TO postgres;

--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: varieties; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.varieties (
    id integer NOT NULL,
    name character varying(255) NOT NULL
);


ALTER TABLE public.varieties OWNER TO postgres;

--
-- Name: varieties_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.varieties_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.varieties_id_seq OWNER TO postgres;

--
-- Name: varieties_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.varieties_id_seq OWNED BY public.varieties.id;


--
-- Name: auctionBids id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."auctionBids" ALTER COLUMN id SET DEFAULT nextval('public.auctionbids_id_seq'::regclass);


--
-- Name: auctionHistory id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."auctionHistory" ALTER COLUMN id SET DEFAULT nextval('public.auctionhistory_id_seq'::regclass);


--
-- Name: auctions id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.auctions ALTER COLUMN id SET DEFAULT nextval('public.auctions_id_seq'::regclass);


--
-- Name: buyerRequests id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."buyerRequests" ALTER COLUMN id SET DEFAULT nextval('public.buyer_requests_id_seq'::regclass);


--
-- Name: certificateRequests id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."certificateRequests" ALTER COLUMN id SET DEFAULT nextval('public.certificate_requests_id_seq'::regclass);


--
-- Name: certificateTypes id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."certificateTypes" ALTER COLUMN id SET DEFAULT nextval('public.certificate_types_id_seq'::regclass);


--
-- Name: cultureRipenessDeliveryRules id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."cultureRipenessDeliveryRules" ALTER COLUMN id SET DEFAULT nextval('public.cultureripenessdeliveryrules_id_seq'::regclass);


--
-- Name: customers id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customers ALTER COLUMN id SET DEFAULT nextval('public.customers_id_seq'::regclass);


--
-- Name: dietTableProducts id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."dietTableProducts" ALTER COLUMN id SET DEFAULT nextval('public.diet_table_products_id_seq'::regclass);


--
-- Name: dietTables id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."dietTables" ALTER COLUMN id SET DEFAULT nextval('public.diet_tables_id_seq'::regclass);


--
-- Name: farmerCertificates id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."farmerCertificates" ALTER COLUMN id SET DEFAULT nextval('public.farmer_certificates_id_seq'::regclass);


--
-- Name: farmerSubscriptions id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."farmerSubscriptions" ALTER COLUMN id SET DEFAULT nextval('public.farmer_subscriptions_id_seq'::regclass);


--
-- Name: freshness id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.freshness ALTER COLUMN id SET DEFAULT nextval('public.freshness_id_seq'::regclass);


--
-- Name: locationProduct id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."locationProduct" ALTER COLUMN id SET DEFAULT nextval('public.locationproduct_id_seq'::regclass);


--
-- Name: namesObjects id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."namesObjects" ALTER COLUMN id SET DEFAULT nextval('public."namesObjects_id_seq"'::regclass);


--
-- Name: places id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.places ALTER COLUMN id SET DEFAULT nextval('public.places_id_seq'::regclass);


--
-- Name: productCategories id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."productCategories" ALTER COLUMN id SET DEFAULT nextval('public.productcategories_id_seq'::regclass);


--
-- Name: productCategory id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."productCategory" ALTER COLUMN id SET DEFAULT nextval('public.productcategory_id_seq'::regclass);


--
-- Name: productCopies id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."productCopies" ALTER COLUMN id SET DEFAULT nextval('public.productcopies_id_seq'::regclass);


--
-- Name: productDimensions id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."productDimensions" ALTER COLUMN id SET DEFAULT nextval('public.productdimensions_id_seq'::regclass);


--
-- Name: productonSupplierPlace id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."productonSupplierPlace" ALTER COLUMN id SET DEFAULT nextval('public.productonsupplierplace_id_seq'::regclass);


--
-- Name: products id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products ALTER COLUMN id SET DEFAULT nextval('public.products_id_seq'::regclass);


--
-- Name: purchases id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchases ALTER COLUMN id SET DEFAULT nextval('public.purchases_id_seq'::regclass);


--
-- Name: requestResponses id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."requestResponses" ALTER COLUMN id SET DEFAULT nextval('public.request_responses_id_seq'::regclass);


--
-- Name: roles id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roles ALTER COLUMN id SET DEFAULT nextval('public.roles_id_seq'::regclass);


--
-- Name: supplierCategories id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."supplierCategories" ALTER COLUMN id SET DEFAULT nextval('public.suppliercategories_id_seq'::regclass);


--
-- Name: supplierCopies id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."supplierCopies" ALTER COLUMN id SET DEFAULT nextval('public.suppliercopy_id_seq'::regclass);


--
-- Name: supplierPlaces id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."supplierPlaces" ALTER COLUMN id SET DEFAULT nextval('public.supplierplaces_id_seq'::regclass);


--
-- Name: supplierPlacesProducts id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."supplierPlacesProducts" ALTER COLUMN id SET DEFAULT nextval('public.supplierplacesproducts_id_seq'::regclass);


--
-- Name: suppliers id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.suppliers ALTER COLUMN id SET DEFAULT nextval('public.suppliers_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: varieties id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.varieties ALTER COLUMN id SET DEFAULT nextval('public.varieties_id_seq'::regclass);

--
-- Data for Name: topology; Type: TABLE DATA; Schema: topology; Owner: postgres
--

COPY topology.topology (id, name, srid, "precision", hasz, useslargeids) FROM stdin;
\.


--
-- Data for Name: layer; Type: TABLE DATA; Schema: topology; Owner: postgres
--

COPY topology.layer (topology_id, layer_id, schema_name, table_name, feature_column, feature_type, level, child_id) FROM stdin;
\.


--
-- Name: auctionbids_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.auctionbids_id_seq', 2, true);


--
-- Name: auctionhistory_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.auctionhistory_id_seq', 4, true);


--
-- Name: auctions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.auctions_id_seq', 3, true);


--
-- Name: buyer_requests_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.buyer_requests_id_seq', 1, false);


--
-- Name: certificate_requests_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.certificate_requests_id_seq', 1, false);


--
-- Name: certificate_types_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.certificate_types_id_seq', 5, true);


--
-- Name: cultureripenessdeliveryrules_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.cultureripenessdeliveryrules_id_seq', 1, false);


--
-- Name: customers_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.customers_id_seq', 1, true);


--
-- Name: diet_table_products_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.diet_table_products_id_seq', 30, true);


--
-- Name: diet_tables_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.diet_tables_id_seq', 10, true);


--
-- Name: farmer_certificates_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.farmer_certificates_id_seq', 7, true);


--
-- Name: farmer_subscriptions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.farmer_subscriptions_id_seq', 7, true);


--
-- Name: freshness_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.freshness_id_seq', 4, true);


--
-- Name: locationproduct_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.locationproduct_id_seq', 3, true);


--
-- Name: namesObjects_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public."namesObjects_id_seq"', 75, true);


--
-- Name: places_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.places_id_seq', 107, true);


--
-- Name: productcategories_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.productcategories_id_seq', 622, true);


--
-- Name: productcategory_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.productcategory_id_seq', 3, true);


--
-- Name: productcopies_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.productcopies_id_seq', 635, true);


--
-- Name: productdimensions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.productdimensions_id_seq', 6, true);


--
-- Name: productonsupplierplace_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.productonsupplierplace_id_seq', 1, false);


--
-- Name: products_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.products_id_seq', 635, true);


--
-- Name: purchases_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.purchases_id_seq', 1, true);


--
-- Name: request_responses_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.request_responses_id_seq', 1, false);


--
-- Name: roles_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.roles_id_seq', 3, true);


--
-- Name: suppliercategories_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.suppliercategories_id_seq', 1, false);


--
-- Name: suppliercopy_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.suppliercopy_id_seq', 84, true);


--
-- Name: supplierplaces_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.supplierplaces_id_seq', 107, true);


--
-- Name: supplierplacesproducts_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.supplierplacesproducts_id_seq', 629, true);


--
-- Name: suppliers_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.suppliers_id_seq', 84, true);


--
-- Name: users_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.users_id_seq', 93, true);


--
-- Name: varieties_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.varieties_id_seq', 35, true);


--
-- Name: topology_id_seq; Type: SEQUENCE SET; Schema: topology; Owner: postgres
--

SELECT pg_catalog.setval('topology.topology_id_seq', 1, false);


--
-- Name: auctionBids auctionbids_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."auctionBids"
    ADD CONSTRAINT auctionbids_pkey PRIMARY KEY (id);


--
-- Name: auctionHistory auctionhistory_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."auctionHistory"
    ADD CONSTRAINT auctionhistory_pkey PRIMARY KEY (id);


--
-- Name: auctions auctions_lotnumber_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.auctions
    ADD CONSTRAINT auctions_lotnumber_key UNIQUE ("lotNumber");


--
-- Name: auctions auctions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.auctions
    ADD CONSTRAINT auctions_pkey PRIMARY KEY (id);


--
-- Name: buyerRequests buyer_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."buyerRequests"
    ADD CONSTRAINT buyer_requests_pkey PRIMARY KEY (id);


--
-- Name: certificateRequests certificate_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."certificateRequests"
    ADD CONSTRAINT certificate_requests_pkey PRIMARY KEY (id);


--
-- Name: certificateTypes certificate_types_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."certificateTypes"
    ADD CONSTRAINT certificate_types_pkey PRIMARY KEY (id);


--
-- Name: countries countries_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.countries
    ADD CONSTRAINT countries_pkey PRIMARY KEY (id);


--
-- Name: cultureRipenessDeliveryRules cultureripenessdeliveryrules_nameobject_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."cultureRipenessDeliveryRules"
    ADD CONSTRAINT cultureripenessdeliveryrules_nameobject_id_key UNIQUE (idNameObject);


--
-- Name: cultureRipenessDeliveryRules cultureripenessdeliveryrules_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."cultureRipenessDeliveryRules"
    ADD CONSTRAINT cultureripenessdeliveryrules_pkey PRIMARY KEY (id);


--
-- Name: customers customers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (id);


--
-- Name: dietTableProducts diet_table_products_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."dietTableProducts"
    ADD CONSTRAINT diet_table_products_pkey PRIMARY KEY (id);


--
-- Name: dietTableProducts diet_table_products_table_id_product_id_variety_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."dietTableProducts"
    ADD CONSTRAINT diet_table_products_table_id_product_id_variety_id_key UNIQUE ("idTabel", "idProduct", "idVariety");


--
-- Name: dietTables diet_tables_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."dietTables"
    ADD CONSTRAINT diet_tables_pkey PRIMARY KEY (id);


--
-- Name: farmerCertificates farmer_certificates_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."farmerCertificates"
    ADD CONSTRAINT farmer_certificates_pkey PRIMARY KEY (id);


--
-- Name: farmerSubscriptions farmer_subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."farmerSubscriptions"
    ADD CONSTRAINT farmer_subscriptions_pkey PRIMARY KEY (id);


--
-- Name: freshness freshness_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.freshness
    ADD CONSTRAINT freshness_pkey PRIMARY KEY (id);


--
-- Name: locationProduct locationproduct_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."locationProduct"
    ADD CONSTRAINT locationproduct_pkey PRIMARY KEY (id);


--
-- Name: namesObjects namesObjects_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."namesObjects"
    ADD CONSTRAINT "namesObjects_pkey" PRIMARY KEY (id);


--
-- Name: places places_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.places
    ADD CONSTRAINT places_pkey PRIMARY KEY (id);


--
-- Name: productCategories productcategories_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."productCategories"
    ADD CONSTRAINT productcategories_pkey PRIMARY KEY (id);


--
-- Name: productCategory productcategory_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."productCategory"
    ADD CONSTRAINT productcategory_pkey PRIMARY KEY (id);


--
-- Name: productCopies productcopies_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."productCopies"
    ADD CONSTRAINT productcopies_pkey PRIMARY KEY (id);


--
-- Name: productDimensions productdimensions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."productDimensions"
    ADD CONSTRAINT productdimensions_pkey PRIMARY KEY (id);


--
-- Name: productonSupplierPlace productonsupplierplace_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."productonSupplierPlace"
    ADD CONSTRAINT productonsupplierplace_pkey PRIMARY KEY (id);


--
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (id);


--
-- Name: purchases purchases_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchases
    ADD CONSTRAINT purchases_pkey PRIMARY KEY (id);


--
-- Name: requestResponses request_responses_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."requestResponses"
    ADD CONSTRAINT request_responses_pkey PRIMARY KEY (id);


--
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (id);


--
-- Name: supplierCategories suppliercategories_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."supplierCategories"
    ADD CONSTRAINT suppliercategories_pkey PRIMARY KEY (id);


--
-- Name: supplierCopies suppliercopy_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."supplierCopies"
    ADD CONSTRAINT suppliercopy_pkey PRIMARY KEY (id);


--
-- Name: supplierPlaces supplierplaces_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."supplierPlaces"
    ADD CONSTRAINT supplierplaces_pkey PRIMARY KEY (id);


--
-- Name: supplierPlacesProducts supplierplacesproducts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."supplierPlacesProducts"
    ADD CONSTRAINT supplierplacesproducts_pkey PRIMARY KEY (id);


--
-- Name: suppliers suppliers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.suppliers
    ADD CONSTRAINT suppliers_pkey PRIMARY KEY (id);


--
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: users users_username_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_username_key UNIQUE ("userName");


--
-- Name: varieties varieties_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.varieties
    ADD CONSTRAINT varieties_pkey PRIMARY KEY (id);


--
-- Name: idx_buyer_requests_expires_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_buyer_requests_expires_at ON public."buyerRequests" USING btree ("expiresAt");


--
-- Name: idx_buyer_requests_object; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_buyer_requests_object ON public."buyerRequests" USING btree ("idObject");


--
-- Name: idx_buyer_requests_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_buyer_requests_status ON public."buyerRequests" USING btree (status);


--
-- Name: idx_buyer_requests_user; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_buyer_requests_user ON public."buyerRequests" USING btree ("idUser");


--
-- Name: idx_certificate_requests_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_certificate_requests_status ON public."certificateRequests" USING btree (status);


--
-- Name: idx_certificate_requests_supplier; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_certificate_requests_supplier ON public."certificateRequests" USING btree ("idSupplier");


--
-- Name: idx_farmer_certificates_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_farmer_certificates_status ON public."farmerCertificates" USING btree (status);


--
-- Name: idx_farmer_certificates_supplier; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_farmer_certificates_supplier ON public."farmerCertificates" USING btree ("idSupplier");


--
-- Name: idx_places_boundary; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_places_boundary ON public.places USING gist (boundaries);


--
-- Name: idx_purchases_customer; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_purchases_customer ON public.purchases USING btree ("idCustomer");


--
-- Name: idx_purchases_product; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_purchases_product ON public.purchases USING btree ("idProduct");


--
-- Name: idx_purchases_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_purchases_status ON public.purchases USING btree (status);


--
-- Name: idx_purchases_supplier; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_purchases_supplier ON public.purchases USING btree ("idSupplier");


--
-- Name: idx_subscriptions_customer; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_subscriptions_customer ON public."farmerSubscriptions" USING btree ("idCustomer");


--
-- Name: idx_subscriptions_supplier; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_subscriptions_supplier ON public."farmerSubscriptions" USING btree ("idSupplier");


--
-- Name: uq_request_responses_request_supplier; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX uq_request_responses_request_supplier ON public."requestResponses" USING btree ("idRequest", "idSupplier");


--
-- Name: buyerRequests trg_buyer_requests_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_buyer_requests_updated_at BEFORE UPDATE ON public."buyerRequests" FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: requestResponses trg_request_responses_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_request_responses_updated_at BEFORE UPDATE ON public."requestResponses" FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: productCopies trg_update_farmer_rating; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_update_farmer_rating AFTER INSERT OR UPDATE OF rating ON public."productCopies" FOR EACH ROW EXECUTE FUNCTION public.update_farmer_rating();


--
-- Name: products FK_Object; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT "FK_Object" FOREIGN KEY ("idObject") REFERENCES public."namesObjects"(id) NOT VALID;


--
-- Name: supplierPlacesProducts FK_Product; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."supplierPlacesProducts"
    ADD CONSTRAINT "FK_Product" FOREIGN KEY ("idProduct") REFERENCES public.products(id) NOT VALID;


--
-- Name: supplierPlacesProducts FK_SupplierPlace; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."supplierPlacesProducts"
    ADD CONSTRAINT "FK_SupplierPlace" FOREIGN KEY ("idSupplierPlace") REFERENCES public."supplierPlaces"(id) NOT VALID;


--
-- Name: auctionBids auctionbids_idauction_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."auctionBids"
    ADD CONSTRAINT auctionbids_idauction_fkey FOREIGN KEY ("idAuction") REFERENCES public.auctions(id) ON DELETE CASCADE;


--
-- Name: auctionBids auctionbids_iduser_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."auctionBids"
    ADD CONSTRAINT auctionbids_iduser_fkey FOREIGN KEY ("idUser") REFERENCES public.users(id);


--
-- Name: auctionHistory auctionhistory_changedby_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."auctionHistory"
    ADD CONSTRAINT auctionhistory_changedby_fkey FOREIGN KEY ("changedBy") REFERENCES public.users(id);


--
-- Name: auctionHistory auctionhistory_idauction_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."auctionHistory"
    ADD CONSTRAINT auctionhistory_idauction_fkey FOREIGN KEY ("idAuction") REFERENCES public.auctions(id) ON DELETE CASCADE;


--
-- Name: auctions auctions_idplace_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.auctions
    ADD CONSTRAINT auctions_idplace_fkey FOREIGN KEY ("idPlace") REFERENCES public."supplierPlaces"(id);


--
-- Name: auctions auctions_idproduct_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.auctions
    ADD CONSTRAINT auctions_idproduct_fkey FOREIGN KEY ("idProduct") REFERENCES public.products(id);


--
-- Name: auctions auctions_idsupplier_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.auctions
    ADD CONSTRAINT auctions_idsupplier_fkey FOREIGN KEY ("idSupplier") REFERENCES public.suppliers(id);


--
-- Name: buyerRequests buyer_requests_object_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."buyerRequests"
    ADD CONSTRAINT buyer_requests_object_fk FOREIGN KEY ("idObject") REFERENCES public."namesObjects"(id) ON DELETE RESTRICT;


--
-- Name: buyerRequests buyer_requests_user_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."buyerRequests"
    ADD CONSTRAINT buyer_requests_user_fk FOREIGN KEY ("idUser") REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: certificateRequests certificate_requests_certificate_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."certificateRequests"
    ADD CONSTRAINT certificate_requests_certificate_type_id_fkey FOREIGN KEY ("IdCertificateType") REFERENCES public."certificateTypes"(id);


--
-- Name: certificateRequests certificate_requests_processed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."certificateRequests"
    ADD CONSTRAINT certificate_requests_processed_by_fkey FOREIGN KEY ("processedBy") REFERENCES public.users(id);


--
-- Name: certificateRequests certificate_requests_supplier_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."certificateRequests"
    ADD CONSTRAINT certificate_requests_supplier_id_fkey FOREIGN KEY ("idSupplier") REFERENCES public.suppliers(id) ON DELETE CASCADE;


--
-- Name: places country_place_FK; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.places
    ADD CONSTRAINT "country_place_FK" FOREIGN KEY ("idCountry") REFERENCES public.countries(id) NOT VALID;


--
-- Name: cultureRipenessDeliveryRules cultureripenessdeliveryrules_nameobject_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."cultureRipenessDeliveryRules"
    ADD CONSTRAINT cultureripenessdeliveryrules_nameobject_id_fkey FOREIGN KEY (idNameObject) REFERENCES public."namesObjects"(id) ON DELETE CASCADE;


--
-- Name: customers customer_user_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customer_user_fk FOREIGN KEY ("idUser") REFERENCES public.users(id) NOT VALID;


--
-- Name: dietTableProducts diet_table_products_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."dietTableProducts"
    ADD CONSTRAINT diet_table_products_product_id_fkey FOREIGN KEY ("idProduct") REFERENCES public.products(id) ON DELETE CASCADE;


--
-- Name: dietTableProducts diet_table_products_table_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."dietTableProducts"
    ADD CONSTRAINT diet_table_products_table_id_fkey FOREIGN KEY ("idTabel") REFERENCES public."dietTables"(id) ON DELETE CASCADE;


--
-- Name: dietTableProducts diet_table_products_variety_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."dietTableProducts"
    ADD CONSTRAINT diet_table_products_variety_id_fkey FOREIGN KEY ("idVariety") REFERENCES public.varieties(id);


--
-- Name: farmerCertificates farmer_certificates_certificate_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."farmerCertificates"
    ADD CONSTRAINT farmer_certificates_certificate_type_id_fkey FOREIGN KEY ("IdCertificateType") REFERENCES public."certificateTypes"(id);


--
-- Name: farmerCertificates farmer_certificates_supplier_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."farmerCertificates"
    ADD CONSTRAINT farmer_certificates_supplier_id_fkey FOREIGN KEY ("idSupplier") REFERENCES public.suppliers(id) ON DELETE CASCADE;


--
-- Name: farmerCertificates farmer_certificates_verified_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."farmerCertificates"
    ADD CONSTRAINT farmer_certificates_verified_by_fkey FOREIGN KEY ("verifiedBy") REFERENCES public.users(id);


--
-- Name: farmerSubscriptions farmer_subscriptions_idcustomer_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."farmerSubscriptions"
    ADD CONSTRAINT farmer_subscriptions_idcustomer_fkey FOREIGN KEY ("idCustomer") REFERENCES public.customers(id);


--
-- Name: farmerSubscriptions farmer_subscriptions_idsupplier_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."farmerSubscriptions"
    ADD CONSTRAINT farmer_subscriptions_idsupplier_fkey FOREIGN KEY ("idSupplier") REFERENCES public.suppliers(id);


--
-- Name: suppliers fk_supplieruser; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.suppliers
    ADD CONSTRAINT fk_supplieruser FOREIGN KEY ("idUser") REFERENCES public.users(id);


--
-- Name: namesObjects namesObjects_idvariety_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."namesObjects"
    ADD CONSTRAINT "namesObjects_idvariety_fkey" FOREIGN KEY ("idVariety") REFERENCES public.varieties(id);


--
-- Name: productCategories productcategories_idcategory_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."productCategories"
    ADD CONSTRAINT productcategories_idcategory_fkey FOREIGN KEY ("idCategory") REFERENCES public."productCategory"(id);


--
-- Name: productCategories productcategories_idproduct_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."productCategories"
    ADD CONSTRAINT productcategories_idproduct_fkey FOREIGN KEY ("idProduct") REFERENCES public.products(id);


--
-- Name: productCopies productcopies_iddimension_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."productCopies"
    ADD CONSTRAINT productcopies_iddimension_fkey FOREIGN KEY ("idDimension") REFERENCES public."productDimensions"(id);


--
-- Name: productCopies productcopies_idfreshness; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."productCopies"
    ADD CONSTRAINT productcopies_idfreshness FOREIGN KEY ("idFreshness") REFERENCES public.freshness(id) NOT VALID;


--
-- Name: productCopies productcopies_idlocationproduct_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."productCopies"
    ADD CONSTRAINT productcopies_idlocationproduct_fkey FOREIGN KEY ("idLocationProduct") REFERENCES public."locationProduct"(id) NOT VALID;


--
-- Name: productCopies productcopies_idproduct_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."productCopies"
    ADD CONSTRAINT productcopies_idproduct_fkey FOREIGN KEY ("idProduct") REFERENCES public.products(id);


--
-- Name: productonSupplierPlace productonsupplierplace_idproductcategory_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."productonSupplierPlace"
    ADD CONSTRAINT productonsupplierplace_idproductcategory_fkey FOREIGN KEY ("idProductCategory") REFERENCES public."productCategory"(id);


--
-- Name: productonSupplierPlace productonsupplierplace_idsupplierplace_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."productonSupplierPlace"
    ADD CONSTRAINT productonsupplierplace_idsupplierplace_fkey FOREIGN KEY ("idSupplierPlace") REFERENCES public."supplierPlaces"(id);


--
-- Name: purchases purchases_idcustomer_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchases
    ADD CONSTRAINT purchases_idcustomer_fkey FOREIGN KEY ("idCustomer") REFERENCES public.users(id);


--
-- Name: purchases purchases_idplace_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchases
    ADD CONSTRAINT purchases_idplace_fkey FOREIGN KEY ("idPlace") REFERENCES public.places(id);


--
-- Name: purchases purchases_idproduct_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchases
    ADD CONSTRAINT purchases_idproduct_fkey FOREIGN KEY ("idProduct") REFERENCES public.products(id);


--
-- Name: purchases purchases_idsupplier_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchases
    ADD CONSTRAINT purchases_idsupplier_fkey FOREIGN KEY ("idSupplier") REFERENCES public.suppliers(id);


--
-- Name: requestResponses request_responses_request_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."requestResponses"
    ADD CONSTRAINT request_responses_request_fk FOREIGN KEY ("idRequest") REFERENCES public."buyerRequests"(id) ON DELETE CASCADE;


--
-- Name: requestResponses request_responses_supplier_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."requestResponses"
    ADD CONSTRAINT request_responses_supplier_fk FOREIGN KEY ("idSupplier") REFERENCES public.suppliers(id) ON DELETE CASCADE;


--
-- Name: supplierCopies suppliercopy_idsupplier_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."supplierCopies"
    ADD CONSTRAINT suppliercopy_idsupplier_fkey FOREIGN KEY ("idSupplier") REFERENCES public.suppliers(id);


--
-- Name: supplierPlaces supplierplaces_idplace_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."supplierPlaces"
    ADD CONSTRAINT supplierplaces_idplace_fkey FOREIGN KEY ("idPlace") REFERENCES public.places(id);


--
-- Name: supplierPlaces supplierplaces_idsupplier_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."supplierPlaces"
    ADD CONSTRAINT supplierplaces_idsupplier_fkey FOREIGN KEY ("idSupplier") REFERENCES public.suppliers(id);


--
-- Name: users users_roleid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_roleid_fkey FOREIGN KEY ("idRole") REFERENCES public.roles(id);


--
-- PostgreSQL database dump complete
--


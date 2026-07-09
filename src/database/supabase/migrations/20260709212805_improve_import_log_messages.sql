create or replace function fn_import_log_display_value(p_value text)
returns text
language sql
immutable
as $$
  select case
    when p_value is null or nullif(btrim(p_value), '') is null or btrim(p_value) = '<null>'
      then 'vazio'
    else '"' || replace(btrim(p_value), '"', '""') || '"'
  end
$$;

create or replace function fn_import_log_message_detail(p_message text, p_prefix text)
returns text
language sql
immutable
as $$
  select btrim(substring(p_message from char_length(p_prefix) + 1))
$$;

create or replace function fn_format_import_log_message(
  p_import_id uuid,
  p_message text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_message text := coalesce(p_message, '');
  v_detail text;
  v_distributor_code text;
  v_distributor_cnpj text;
  v_expected_distributor text;
begin
  if left(v_message, char_length('validator: ')) = 'validator: ' then
    v_message := substring(v_message from char_length('validator: ') + 1);
  end if;

  select d.code, d.cnpj
  into v_distributor_code, v_distributor_cnpj
  from file_imports fi
  join distributors d on d.id = fi.distributor_id
  where fi.id = p_import_id;

  v_expected_distributor := concat_ws(
    ' ou ',
    case
      when nullif(btrim(coalesce(v_distributor_code, '')), '') is not null
        then 'código ' || btrim(v_distributor_code)
    end,
    case
      when nullif(btrim(coalesce(v_distributor_cnpj, '')), '') is not null
        then 'CNPJ ' || btrim(v_distributor_cnpj)
    end
  );

  if nullif(v_expected_distributor, '') is null then
    v_expected_distributor := 'o distribuidor vinculado à conta';
  end if;

  if left(v_message, char_length('unauthorized distributor:')) = 'unauthorized distributor:' then
    v_detail := fn_import_log_message_detail(v_message, 'unauthorized distributor:');
    return 'Distribuidor da planilha não corresponde ao distribuidor da conta. Valor informado: '
      || fn_import_log_display_value(v_detail)
      || '. Esperado: '
      || v_expected_distributor
      || '. Ajuste a coluna Distribuidor/CNPJ Distribuidor ou o cadastro do distribuidor antes de importar novamente.';
  end if;

  if left(v_message, char_length('missing required columns:')) = 'missing required columns:' then
    v_detail := fn_import_log_message_detail(v_message, 'missing required columns:');
    return 'Layout inválido: o arquivo não contém as colunas obrigatórias '
      || fn_import_log_display_value(v_detail)
      || '. Confira o modelo esperado para este tipo de importação na aba Arquivos > Configuração.';
  end if;

  if v_message = 'no data rows found' then
    return 'O arquivo não possui linhas de dados após o cabeçalho. Preencha ao menos uma linha e tente novamente.';
  end if;

  if left(v_message, char_length('import ')) = 'import '
    and right(v_message, char_length(' not found')) = ' not found' then
    return 'Registro de importação não encontrado. Envie o arquivo novamente.';
  end if;

  if left(v_message, char_length('no ETL spec for target table')) = 'no ETL spec for target table' then
    return 'Tipo de importação ainda não configurado no pipeline AWS. Verifique a configuração do tipo de arquivo.';
  end if;

  if v_message = 'missing customer pdv code' then
    return 'Cliente sem código PDV. Preencha a coluna PDV/Código PDV.';
  end if;

  if v_message = 'missing legal name' then
    return 'Cliente sem razão social. Preencha a coluna Razão Social.';
  end if;

  if v_message = 'missing product ean' then
    return 'Produto sem EAN. Preencha a coluna EAN.';
  end if;

  if v_message = 'missing product name' then
    return 'Produto sem descrição. Preencha a coluna Descrição/Nome do Produto.';
  end if;

  if v_message = 'missing macro category' then
    return 'Produto sem macrocategoria. Preencha a coluna Macrocategoria.';
  end if;

  if v_message = 'missing category' then
    return 'Produto sem categoria. Preencha a coluna Categoria.';
  end if;

  if v_message = 'missing subcategory' then
    return 'Produto sem subcategoria. Preencha a coluna Subcategoria.';
  end if;

  if v_message = 'unknown product hierarchy' then
    return 'Hierarquia do produto não encontrada. Confira Macrocategoria, Categoria e Subcategoria na mesma linha.';
  end if;

  if v_message = 'missing seller code' then
    return 'Vendedor sem código. Preencha a coluna Código do Vendedor/Vendedor.';
  end if;

  if v_message = 'missing seller name' then
    return 'Vendedor sem nome. Preencha a coluna Nome do Vendedor.';
  end if;

  if v_message = 'missing supervisor code' then
    return 'Vendedor sem supervisor. Preencha a coluna Código do Supervisor/Supervisor.';
  end if;

  if v_message = 'missing target values' then
    return 'Meta sem valor e sem volume. Preencha ao menos uma das colunas Valor ou Quantidade.';
  end if;

  if left(v_message, char_length('unknown customer code/cnpj:')) = 'unknown customer code/cnpj:' then
    v_detail := fn_import_log_message_detail(v_message, 'unknown customer code/cnpj:');
    return 'Cliente não encontrado para este distribuidor. Valor informado: '
      || fn_import_log_display_value(v_detail)
      || '. Importe ou ajuste Clientes antes de importar Sell Out ou Meta.';
  end if;

  if left(v_message, char_length('unknown customer cnpj:')) = 'unknown customer cnpj:' then
    v_detail := fn_import_log_message_detail(v_message, 'unknown customer cnpj:');
    return 'Cliente não encontrado para este distribuidor. CNPJ informado: '
      || fn_import_log_display_value(v_detail)
      || '. Importe ou ajuste Clientes antes de importar Sell Out.';
  end if;

  if left(v_message, char_length('unknown product ean:')) = 'unknown product ean:' then
    v_detail := fn_import_log_message_detail(v_message, 'unknown product ean:');
    return 'Produto não encontrado para este distribuidor. EAN informado: '
      || fn_import_log_display_value(v_detail)
      || '. Importe ou ajuste Produtos antes de importar Sell In, Sell Out ou Meta.';
  end if;

  if left(v_message, char_length('unknown supervisor code:')) = 'unknown supervisor code:' then
    v_detail := fn_import_log_message_detail(v_message, 'unknown supervisor code:');
    return 'Supervisor não encontrado para este distribuidor. Código informado: '
      || fn_import_log_display_value(v_detail)
      || '. Confira a coluna Supervisor/Código do Supervisor.';
  end if;

  if left(v_message, char_length('invalid invoice_date:')) = 'invalid invoice_date:' then
    v_detail := fn_import_log_message_detail(v_message, 'invalid invoice_date:');
    return 'Data de faturamento inválida: '
      || fn_import_log_display_value(v_detail)
      || '. Use uma data válida no formato DD/MM/AAAA ou AAAA-MM-DD.';
  end if;

  if left(v_message, char_length('invalid delivery_date:')) = 'invalid delivery_date:' then
    v_detail := fn_import_log_message_detail(v_message, 'invalid delivery_date:');
    return 'Data de entrega inválida: '
      || fn_import_log_display_value(v_detail)
      || '. Use uma data válida no formato DD/MM/AAAA ou AAAA-MM-DD, ou deixe em branco.';
  end if;

  if left(v_message, char_length('invalid target_date:')) = 'invalid target_date:' then
    v_detail := fn_import_log_message_detail(v_message, 'invalid target_date:');
    return 'Data da meta inválida: '
      || fn_import_log_display_value(v_detail)
      || '. Use uma data válida no formato DD/MM/AAAA ou AAAA-MM-DD.';
  end if;

  if left(v_message, char_length('invalid quantity:')) = 'invalid quantity:' then
    v_detail := fn_import_log_message_detail(v_message, 'invalid quantity:');
    return 'Quantidade inválida: '
      || fn_import_log_display_value(v_detail)
      || '. Use apenas números; para Sell In e Sell Out a quantidade deve ser maior que zero.';
  end if;

  if left(v_message, char_length('invalid gross_value:')) = 'invalid gross_value:' then
    v_detail := fn_import_log_message_detail(v_message, 'invalid gross_value:');
    return 'Valor inválido: '
      || fn_import_log_display_value(v_detail)
      || '. Use apenas números, por exemplo 1234,56.';
  end if;

  if left(v_message, char_length('invalid units_per_pack:')) = 'invalid units_per_pack:' then
    v_detail := fn_import_log_message_detail(v_message, 'invalid units_per_pack:');
    return 'Unidades por caixa inválida: '
      || fn_import_log_display_value(v_detail)
      || '. Use um número maior que zero.';
  end if;

  if left(v_message, char_length('invalid box_count:')) = 'invalid box_count:' then
    v_detail := fn_import_log_message_detail(v_message, 'invalid box_count:');
    return 'Quantidade de caixas inválida: '
      || fn_import_log_display_value(v_detail)
      || '. Use apenas números ou deixe em branco.';
  end if;

  if left(v_message, char_length('invalid portfolio_size:')) = 'invalid portfolio_size:' then
    v_detail := fn_import_log_message_detail(v_message, 'invalid portfolio_size:');
    return 'Tamanho da carteira inválido: '
      || fn_import_log_display_value(v_detail)
      || '. Use apenas números inteiros ou deixe em branco.';
  end if;

  if p_message is distinct from v_message then
    return 'Erro de validação do arquivo: ' || v_message;
  end if;

  return p_message;
end;
$$;

create or replace function trg_format_import_log_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.message := fn_format_import_log_message(new.import_id, new.message);
  return new;
end;
$$;

drop trigger if exists file_import_logs_format_message_before_insert on file_import_logs;

create trigger file_import_logs_format_message_before_insert
before insert on file_import_logs
for each row
execute function trg_format_import_log_message();

update file_import_logs
set message = fn_format_import_log_message(import_id, message)
where level = 'error';

revoke execute on function fn_import_log_display_value(text) from public, anon, authenticated;
revoke execute on function fn_import_log_message_detail(text, text) from public, anon, authenticated;
revoke execute on function fn_format_import_log_message(uuid, text) from public, anon, authenticated;
revoke execute on function trg_format_import_log_message() from public, anon, authenticated;

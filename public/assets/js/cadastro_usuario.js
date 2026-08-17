'use strict';

document.addEventListener('DOMContentLoaded', () => {
  const form = document.getElementById('cadastroForm');
  const retorno = document.getElementById('mensagem-retorno');
  const roleInput = document.getElementById('role');
  const botoesTipo = document.querySelectorAll('[data-role-option]');
  const camposEmpresa = document.getElementById('camposEmpresa');
  const textoTipoCadastro = document.getElementById('textoTipoCadastro');

  if (!form || !retorno) return;

  manterSomenteDigitos('cpf', 11);
  manterSomenteDigitos('cnpj', 14);

  function safeRedirectPath(target, fallback = '/login.php') {
    try {
      const url = new URL(String(target || fallback), window.location.origin);

      if (url.origin !== window.location.origin) {
        return fallback;
      }

      return `${url.pathname}${url.search}${url.hash}`;
    } catch {
      return fallback;
    }
  }

  function mostrarMensagem(texto, tipo = 'error') {
    retorno.textContent = texto;
    retorno.className = `feedback feedback-${tipo}`;
  }

  function limparMensagem() {
    retorno.textContent = '';
    retorno.className = 'feedback feedback-hidden';
  }

  function manterSomenteDigitos(id, limite) {
    const campo = document.getElementById(id);

    if (!campo) return;

    campo.addEventListener('input', () => {
      campo.value = campo.value.replace(/\D+/g, '').slice(0, limite);
    });
  }

  function valorSeguro(id) {
    const el = document.getElementById(id);
    return el ? el.value.trim() : '';
  }

  function coletarDados() {
    return {
      role: valorSeguro('role') || 'usuario',
      nome: valorSeguro('nome'),
      email: valorSeguro('email').toLowerCase(),
      cpf: valorSeguro('cpf').replace(/\D+/g, ''),
      telefone: valorSeguro('telefone'),
      data_nascimento: valorSeguro('data_nascimento'),
      razao_social: valorSeguro('razao_social'),
      nome_fantasia: valorSeguro('nome_fantasia'),
      cnpj: valorSeguro('cnpj').replace(/\D+/g, ''),
      area_atuacao: valorSeguro('area_atuacao'),
      descricao_empresa: valorSeguro('descricao_empresa'),
      site_url: valorSeguro('site_url'),
      senha: document.getElementById('senha')?.value ?? '',
      confirmarSenha: document.getElementById('confirmarSenha')?.value ?? ''
    };
  }

  function validarCampos(dados) {
    if (!['usuario', 'empresa'].includes(dados.role)) return 'Tipo de cadastro inválido.';
    if (!dados.nome) return 'Informe o nome.';
    if (dados.nome.length < 3) return 'Nome inválido.';
    if (!dados.email) return 'Informe o e-mail.';
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(dados.email)) return 'E-mail inválido.';
    if (!dados.cpf || !/^\d{11}$/.test(dados.cpf)) return 'CPF inválido.';
    if (!dados.telefone) return 'Informe o telefone.';
    if (!dados.data_nascimento) return 'Informe a data de nascimento.';

    if (dados.role === 'empresa') {
      if (!dados.razao_social || dados.razao_social.length < 3) {
        return 'Informe a razão social da empresa.';
      }

      if (!dados.cnpj || !/^\d{14}$/.test(dados.cnpj)) {
        return 'CNPJ inválido. Informe 14 números.';
      }
    }

    if (!dados.senha) return 'Informe a senha.';
    if (dados.senha.length < 8) return 'A senha deve ter pelo menos 8 caracteres.';
    if (dados.senha !== dados.confirmarSenha) return 'As senhas não conferem.';
    return null;
  }

  function atualizarTipoCadastro(role) {
    const tipo = role === 'empresa' ? 'empresa' : 'usuario';

    if (roleInput) {
      roleInput.value = tipo;
    }

    botoesTipo.forEach((botao) => {
      const ativo = botao.getAttribute('data-role-option') === tipo;
      botao.setAttribute('aria-pressed', ativo ? 'true' : 'false');
      botao.classList.toggle('button', ativo);
      botao.classList.toggle('button-outline', !ativo);
    });

    if (camposEmpresa) {
      camposEmpresa.hidden = tipo !== 'empresa';
    }

    ['razao_social', 'cnpj'].forEach((id) => {
      const campo = document.getElementById(id);
      if (campo) {
        campo.required = tipo === 'empresa';
      }
    });

    if (textoTipoCadastro) {
      textoTipoCadastro.textContent = tipo === 'empresa'
        ? 'Cadastro de empresa: informe os dados da pessoa responsável e os dados da organização.'
        : 'Cadastro de usuária/candidata: informe seus dados pessoais para acompanhar oportunidades.';
    }
  }

  botoesTipo.forEach((botao) => {
    botao.addEventListener('click', () => {
      atualizarTipoCadastro(botao.getAttribute('data-role-option') || 'usuario');
      limparMensagem();
    });
  });

  atualizarTipoCadastro(roleInput?.value || 'usuario');

  async function postJsonComTimeout(url, body, csrfToken, timeoutMs = 10000) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);

    try {
      return await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Accept: 'application/json',
          ...(csrfToken ? { 'X-CSRF-Token': csrfToken } : {})
        },
        body: JSON.stringify(body),
        signal: controller.signal,
        credentials: 'same-origin',
        cache: 'no-store'
      });
    } finally {
      clearTimeout(timer);
    }
  }

  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    limparMensagem();

    if (
      !window.ConectaEduca ||
      typeof window.ConectaEduca.encryptHybridEnvelope !== 'function'
    ) {
      mostrarMensagem('O utilitário de criptografia não foi carregado.', 'error');
      return;
    }

    const dados = coletarDados();
    const erroValidacao = validarCampos(dados);

    if (erroValidacao) {
      mostrarMensagem(erroValidacao, 'error');
      return;
    }

    try {
      const envelope = await window.ConectaEduca.encryptHybridEnvelope(dados);
      const csrfToken = window.ConectaEduca.getCsrfToken
        ? window.ConectaEduca.getCsrfToken()
        : null;

      const resposta = await postJsonComTimeout(
        '/api/processa_cadastro_usuario.php',
        envelope,
        csrfToken
      );

      const json = await resposta.json();

      if (!resposta.ok || !json.ok) {
        mostrarMensagem(json.message || 'Não foi possível concluir o cadastro.', 'error');
        return;
      }

      mostrarMensagem(json.message || 'Cadastro realizado com sucesso.', 'success');
      form.reset();
      atualizarTipoCadastro('usuario');

      if (json.redirect) {
        window.setTimeout(() => {
          window.location.assign(safeRedirectPath(json.redirect, '/login.php'));
        }, 900);
      }
    } catch (error) {
      console.error('Erro no cadastro criptografado:', error);
      mostrarMensagem('Erro ao enviar os dados criptografados para o servidor.', 'error');
    }
  });
});
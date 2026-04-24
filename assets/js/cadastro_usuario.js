'use strict';

document.addEventListener('DOMContentLoaded', () => {
  const form = document.getElementById('cadastroForm');
  const retorno = document.getElementById('mensagem-retorno');

  if (!form || !retorno) return;

  function mostrarMensagem(texto, tipo = 'error') {
    retorno.textContent = texto;
    retorno.className = `feedback feedback-${tipo}`;
  }

  function limparMensagem() {
    retorno.textContent = '';
    retorno.className = 'feedback feedback-hidden';
  }

  function valorSeguro(id) {
    const el = document.getElementById(id);
    return el ? el.value.trim() : '';
  }

  function coletarDados() {
    return {
      nome: valorSeguro('nome'),
      email: valorSeguro('email').toLowerCase(),
      cpf: valorSeguro('cpf').replace(/\D+/g, ''),
      telefone: valorSeguro('telefone'),
      data_nascimento: valorSeguro('data_nascimento'),
      cep: valorSeguro('cep'),
      rua: valorSeguro('rua'),
      numero: valorSeguro('numero'),
      cidade: valorSeguro('cidade'),
      estado: valorSeguro('estado').toUpperCase(),
      senha: document.getElementById('senha')?.value ?? ''
    };
  }

  function validarCampos(dados, confirmarSenha) {
    if (!dados.nome) return 'Informe o nome.';
    if (dados.nome.length < 3) return 'Nome inválido.';
    if (!dados.email) return 'Informe o e-mail.';
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(dados.email)) return 'E-mail inválido.';
    if (!dados.cpf || !/^\d{11}$/.test(dados.cpf)) return 'CPF inválido.';
    if (!dados.telefone) return 'Informe o telefone.';
    if (!dados.data_nascimento) return 'Informe a data de nascimento.';
    if (!dados.senha) return 'Informe a senha.';
    if (dados.senha.length < 8) return 'A senha deve ter pelo menos 8 caracteres.';
    if (dados.senha !== confirmarSenha) return 'As senhas não conferem.';
    return null;
  }

  async function postJsonComTimeout(url, body, timeoutMs = 10000) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);

    try {
      const resposta = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        body: JSON.stringify(body),
        signal: controller.signal,
        credentials: 'same-origin',
        cache: 'no-store'
      });

      return resposta;
    } finally {
      clearTimeout(timer);
    }
  }

  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    limparMensagem();

    if (typeof encryptHybrid !== 'function' || typeof decryptHybrid !== 'function') {
      mostrarMensagem('O utilitário de criptografia não foi carregado.', 'error');
      return;
    }

    const confirmarSenha = document.getElementById('confirmarSenha')?.value ?? '';
    const dados = coletarDados();

    const erroValidacao = validarCampos(dados, confirmarSenha);
    if (erroValidacao) {
      mostrarMensagem(erroValidacao, 'error');
      return;
    }

    try {
      const payload = await encryptHybrid(JSON.stringify(dados));

      const resposta = await postJsonComTimeout('/api/processa_cadastro_usuario.php', {
        encryptedKey: payload.encryptedKey,
        iv: payload.iv,
        encryptedMessage: payload.encryptedMessage
      });

      const contentType = resposta.headers.get('content-type') || '';
      if (!contentType.includes('application/json')) {
        mostrarMensagem('Resposta inesperada do servidor.', 'error');
        return;
      }

      const json = await resposta.json();

      if (!json || !json.encryptedMessage) {
        mostrarMensagem(json?.message || 'Não foi possível processar a resposta do servidor.', 'error');
        return;
      }

      const textoDecifrado = await decryptHybrid(json, payload._aesKey, payload._iv);
      if (!textoDecifrado) {
        mostrarMensagem('Falha ao descriptografar a resposta do servidor.', 'error');
        return;
      }

      let retornoServidor;
      try {
        retornoServidor = JSON.parse(textoDecifrado);
      } catch {
        mostrarMensagem('Resposta do servidor em formato inválido.', 'error');
        return;
      }

      if (retornoServidor.success) {
        mostrarMensagem(retornoServidor.message || 'Cadastro realizado com sucesso.', 'success');
        form.reset();
      } else {
        mostrarMensagem(retornoServidor.message || 'Não foi possível concluir o cadastro.', 'error');
      }
    } catch (error) {
      console.error('Erro no cadastro criptografado:', error);
      mostrarMensagem('Erro ao enviar os dados criptografados para o servidor.', 'error');
    }
  });
});
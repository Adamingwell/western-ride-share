export function setupPasswordConfirmation(form) {
  const password = form.querySelector('#password');
  const group = form.querySelector('#password-confirmation');
  const confirmation = group.querySelector('#confirm-password');
  const toggle = group.querySelector('#show-password');
  const error = group.querySelector('#password-match-error');
  let touched = false;

  function syncVisibility() {
    password.type = confirmation.type = toggle.checked ? 'text' : 'password';
  }

  function validate() {
    const mismatch = !group.hidden && touched && confirmation.value !== password.value;
    error.textContent = mismatch ? 'Passwords don’t match.' : '';
    error.hidden = !mismatch;
    if (mismatch) confirmation.setAttribute('aria-invalid', 'true');
    else confirmation.removeAttribute('aria-invalid');
    return !mismatch;
  }

  toggle.addEventListener('change', syncVisibility);
  confirmation.addEventListener('blur', () => {
    if (confirmation.value) touched = true;
    validate();
  });
  password.addEventListener('input', validate);
  confirmation.addEventListener('input', validate);

  return {
    setEnabled(enabled) {
      group.hidden = !enabled;
      confirmation.disabled = !enabled;
      confirmation.required = enabled;
      confirmation.value = '';
      toggle.checked = false;
      touched = false;
      syncVisibility();
      validate();
    },
    check() {
      touched = true;
      if (validate()) return true;
      confirmation.focus();
      return false;
    },
  };
}

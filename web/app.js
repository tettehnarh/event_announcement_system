const apiBase = window.API_BASE || ""; // Set in README or injected later

async function fetchEvents() {
  const res = await fetch(`${apiBase}/events`);
  const data = await res.json();
  const list = document.getElementById('events');
  list.innerHTML = '';
  (data.events || []).forEach(ev => {
    const li = document.createElement('li');
    li.textContent = `${ev.title} - ${ev.date} @ ${ev.location}`;
    list.appendChild(li);
  });
}

async function createEvent(e) {
  e.preventDefault();
  const form = e.target;
  const payload = Object.fromEntries(new FormData(form).entries());
  const res = await fetch(`${apiBase}/events`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload)
  });
  if (!res.ok) {
    alert('Failed to create event');
  }
  await fetchEvents();
  form.reset();
}

async function subscribe(e) {
  e.preventDefault();
  const form = e.target;
  const payload = Object.fromEntries(new FormData(form).entries());
  const res = await fetch(`${apiBase}/subscribe`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload)
  });
  if (res.ok) alert('Check your email to confirm subscription');
}

window.addEventListener('DOMContentLoaded', () => {
  document.getElementById('refresh').addEventListener('click', fetchEvents);
  document.getElementById('eventForm').addEventListener('submit', createEvent);
  document.getElementById('subscribeForm').addEventListener('submit', subscribe);
  fetchEvents();
});


export interface Contact {
  id: string;
  name: string;
  email: string;
}

interface ContactListProps {
  contacts: Contact[];
}

export function ContactList({ contacts }: ContactListProps) {
  return (
    <ul className="contact-list">
      {contacts.map((contact) => (
        <li key={contact.id}>
          <span className="contact-name">{contact.name}</span>
          <span className="contact-email">{contact.email}</span>
        </li>
      ))}
    </ul>
  );
}

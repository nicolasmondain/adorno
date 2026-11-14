import { useState } from 'react';

interface ContactSearchProps {
  onSearch: (query: string) => void;
}

export function ContactSearch({ onSearch }: ContactSearchProps) {
  const [query, setQuery] = useState('');

  return (
    <label>
      Search contacts
      <input
        type="search"
        value={query}
        onChange={(event) => {
          setQuery(event.target.value);
          onSearch(event.target.value);
        }}
      />
    </label>
  );
}

-- Example seed, applied by `libexec/run seed` to an empty slot. Replace with yours.
create table items (id serial primary key, name text not null);
insert into items (name) values ('first'), ('second');

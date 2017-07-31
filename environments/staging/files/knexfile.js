module.exports = {
  staging: {
    client: 'postgresql',
    connection: "${database_url}",
    pool: {
      min: 5,
      max: 32
    },
    migrations: {
      tableName: 'knex_migrations'
    }
  }
};


var host = 'http://test.127.0.0.1.xip.io:8080/static/admin/'
describe('Components', function () {

  beforeEach(function () {
    cy.login()
  })

  it('Loads components page', function () {
    cy.get('a[href="#datasets/components"]').click();
    cy.get('body').should('contain', 'Listing components')
    cy.get('body').should('contain', 'New component')
  })

  it('Creates new component', function () {
    cy.get('a[href="#datasets/components"]').click()
    cy.get('body').contains('New component').click()
    cy.url().should('match', /static\/admin\/index.html#datasets\/components\/new\/\d+/)
    cy.get('#name').type('test component');
    cy.get('#slug').type('testcomponent');
    cy.get('#html').then(elem => {
      elem.val('<html>sample test component</html>')
    })
    cy.get('input[type="submit"]').click();
    cy.reload()
    cy.get('a.uk-button').contains('Back').click()
    cy.get('body').should('contain', 'Listing components')
    cy.get('td').should('contain', 'test component')
  })

  it('Edits a component', function () {
    cy.get('a[href="#datasets/components"]').click()
    cy.contains('test component').parent('tr').within(() => {
      cy.get('i.fa-edit').click()
    })
    cy.url().should('match', /static\/admin\/index.html#datasets\/components\/\d+\/edit/)
    cy.get('body').should('contain', 'Editing component')
    cy.get('#name').invoke('val').should('eq', 'test component')
    cy.get('#name').clear();
    cy.get('#name').type('test component edited');
    cy.get('#slug').invoke('val').should('eq', 'testcomponent')
    cy.get('#slug').clear();
    cy.get('#slug').type('tpedited');
    cy.get('#html').then(elem => {
      elem.val('<html>sample test component edited</html>')
    })
    cy.get('input[type="submit"]').click();
    cy.get('a.uk-button').contains('Back').click()
    cy.get('body').should('contain', 'Listing components')
    cy.get('td').should('contain', 'test component edited')
  })

  it('deletes a component', function () {
    cy.get('a[href="#datasets/components"]').click()
    cy.contains('test component edited').parent('tr').within(() => {
      cy.get('i.fa-trash-alt').click()
    })
    cy.get('div.uk-modal').should('contain', 'Are you sure?')
    cy.get('button').contains('Ok').click()

    cy.get('body').contains('test component edited').should('not.exist')
  })
})
